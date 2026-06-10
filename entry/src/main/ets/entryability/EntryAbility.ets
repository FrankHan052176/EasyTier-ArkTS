import { AbilityConstant, Configuration, UIAbility, Want, WantAgent, wantAgent, wantConstant } from '@kit.AbilityKit';
import { backgroundTaskManager } from '@kit.BackgroundTasksKit';
import { geoLocationManager } from '@kit.LocationKit';
import { window } from '@kit.ArkUI';
import { EventHelper } from '../util/EventHelper';
import { Logger, LogLocate } from '../shared/logging/Logger';
import { BusinessError, deviceInfo, emitter } from '@kit.BasicServicesKit';
import easytier from 'easytier-ohrs';
import { vpnExtension, socket } from '@kit.NetworkKit';
import { JSON, url, util } from '@kit.ArkTS';
import { APP_VERSION, BUILD_TIME, CORE_VERSION } from '../util/info/BuildTime';
import { WindowUtil } from '../WindowUtil';
import { HMRouterMgr } from '@hadss/hmrouter';
import { AppManager } from '../AppManager';
import { sendToast } from '../ToastUtil';
import { isIpAddr } from '../class/config/IP';
import { BottomAnimator } from '../class/animator/BottomAnimator';
import { fileUri, fileIo as fs } from '@kit.CoreFileKit';
import { systemShare } from '@kit.ShareKit';
import { rpc } from '@kit.IPCKit';
import { startRuntimeStatsRecording, stopRuntimeStatsRecording } from '../services/runtime/RuntimeStatsService';
import { buildShareUrlSync, unwrapUrl } from '../util/ShareUtil';
import { updateFavorite } from '../services/form/CommunicationUtil';
import { cancelNotification, publishTextNotification } from '../util/NoticeHelper';
import { ConfigFieldValue, ConfigJson } from '../config/schema/SchemaConfig';
import { RuntimeAggregateState, RuntimeInstanceState } from '../types/runtime/RuntimeTypes';
import { KERNEL_SOCKET_NAME, TunRequestPayload, VpnContinueStateData } from '../infrastructure/bridge/kernel/KernelBridgeTypes'
import { decodeSocketChunk, parseKernelSocketMessage, parseVpnBridgeMessage } from '../infrastructure/bridge/kernel/SocketCodec'
import { CrashLogService } from '../services/crash/CrashLogService'
import { MemoryDiagnosticsService } from '../services/runtime/MemoryDiagnosticsService'
import { RemoteManageService } from '../services/remote/RemoteManageService'
import {
  RemoteConfigMeta,
  RemoteCreateDefaultConfigResult,
  RemoteFieldValueResult,
  RemoteGetConfigResult,
  RemoteGetFieldsResult,
  RemoteHostHandler,
  RemoteRuntimeInstanceLite,
  RemoteRuntimeSummary,
  RemoteSettingsState,
  RemoteSummary
} from '../services/remote/RemoteManageTypes'
import { getDefaultConfig } from '../config/defaults/ConfigDefaults'
import { getHostname } from '../util/Conversion'
import { CLOUD_CONFIG_CHANGED_EVENT } from '../ConfigSyncUtil'

const easytier_release = easytier

class EntryRemoteHostHandler implements RemoteHostHandler {
  private ability: EntryAbility

  constructor(ability: EntryAbility) {
    this.ability = ability
  }

  async waitReady(): Promise<void> {
    await this.ability.remoteWaitReady()
  }

  onRemoteManageConnected(): void {
    this.ability.remoteManageConnected()
  }

  onRemoteManageDisconnected(): void {
    this.ability.remoteManageDisconnected()
  }

  summary(): RemoteSummary {
    return this.ability.remoteSummary()
  }

  listConfigs(): RemoteConfigMeta[] {
    return this.ability.remoteConfigList()
  }

  getConfig(configId: string): RemoteGetConfigResult | undefined {
    return this.ability.remoteGetConfig(configId)
  }

  getRuntimeInstance(configId: string): RuntimeInstanceState | undefined {
    return this.ability.remoteGetRuntimeInstance(configId)
  }

  getConfigFields(configId: string, fields: string[]): RemoteGetFieldsResult {
    return this.ability.remoteGetConfigFields(configId, fields)
  }

  setConfigField(configId: string, field: string, value: ConfigFieldValue): boolean {
    return this.ability.remoteSetConfigField(configId, field, value)
  }

  saveConfig(configId: string, displayName: string, config: ConfigJson): boolean {
    return this.ability.remoteSaveConfig(configId, displayName, config)
  }

  createDefaultConfig(displayName: string): RemoteCreateDefaultConfigResult | undefined {
    return this.ability.remoteCreateDefaultConfig(displayName)
  }

  importConfig(config: ConfigJson, displayName: string): RemoteCreateDefaultConfigResult | undefined {
    return this.ability.remoteImportConfig(config, displayName)
  }

  deleteConfig(configId: string): boolean {
    return this.ability.remoteDeleteConfig(configId)
  }

  renameConfig(configId: string, displayName: string): boolean {
    return this.ability.remoteRenameConfig(configId, displayName)
  }

  startConfig(configId: string): boolean {
    return AppManager.easytier.start(configId)
  }

  stopConfig(configId: string): boolean {
    return AppManager.easytier.stopConfig(configId)
  }

  exportToml(configId: string): string | undefined {
    return easytier.exportToml(configId) ?? undefined
  }

  getSettings(): RemoteSettingsState {
    return this.ability.remoteSettings()
  }

  setSetting(key: string, value: boolean | string): RemoteSettingsState {
    return this.ability.remoteSetSetting(key, value)
  }

  async requestPermission(kind: string): Promise<RemoteSettingsState> {
    return this.ability.remoteRequestPermission(kind)
  }
}

@LogLocate("EntryAbility")
export default class EntryAbility extends UIAbility {
  vpnConnection: vpnExtension.VpnConnection | undefined
  kernelClient: socket.LocalSocket | undefined
  kernelMessageBuffer: string = ''
  kernelSocketConnected: boolean = false
  continuationClient: socket.LocalSocket | undefined
  continuationMessageBuffer: string = ''
  continuationSocketConnected: boolean = false
  private appReadyPromise: Promise<void> = Promise.resolve()
  private remoteManageSnapshotSessionCount: number = 0
  private entrySyncContinuationSocketCallback = () => {
    this.syncContinuationSocket()
  }
  private startBgCallback = (data: emitter.EventData) => {
    let shouldProtect = false
    const cfg = data.data?.cfg as string | undefined
    try {
      if (cfg) {
        const config: ESObject = JSON.parse(cfg)
        shouldProtect = this.shouldProtectProcessNet(config)
      }
    } catch (error) {
    }
    this.prepare_vpn(shouldProtect, () => {
      Logger.info("start_bg_task", this)
      this.connectToKernelSocket(AppManager.uiState.getSocketPath(KERNEL_SOCKET_NAME))
      this.startContinuousTask(cfg ?? '', data.data?.uuid, data.data?.name);
    })
  }
  private stopBgCallback = () => {
    Logger.info("stop_bg_task", this)
    this.stopContinuousTask()
    this.kernelClient?.close()
    this.kernelClient = undefined
    this.kernelSocketConnected = false
    this.kernelMessageBuffer = ''
  }
  private setupTunCallback = (data: emitter.EventData) => {
    Logger.info("setup_tun", this)
    let ip = data.data!.ip as string
    let mask = data.data!.mask as number
    let magicDNS = data.data!.magicDNS as boolean
    let inst_id = data.data!.id as string
    let needExitNode = data.data!.needExitNode as boolean
    let routes = data.data!.routes as string[] | undefined
    this.setup_tun(ip, mask, magicDNS, inst_id, needExitNode, routes)
  }
  private changeIpv4Callback = (data: emitter.EventData) => {
    Logger.info("change_ipv4", this)
    this.vpnConnection?.destroy().catch(() => {
    }).then(() => {
      let ip = data.data!.ip as string
      let mask = data.data!.mask as number
      let magicDNS = data.data!.magicDNS as boolean
      let inst_id = data.data!.id as string
      let needExitNode = data.data!.needExitNode as boolean
      let routes = data.data!.routes as string[] | undefined
      this.setup_tun(ip, mask, magicDNS, inst_id, needExitNode, routes)
    })
  }

  private shouldProtectProcessNet(config?: ConfigJson): boolean {
    return deviceInfo.sdkApiVersion >= 22 && AppManager.uiState.force_global && (config?.exit_nodes?.length ?? 0) > 0
  }

  private activateMissionContinue(): void {
    this.context.setMissionContinueState(AbilityConstant.ContinueState.ACTIVE)
  }

  private deactivateMissionContinue(): void {
    this.context.setMissionContinueState(AbilityConstant.ContinueState.INACTIVE)
  }

  private syncContinuationSocket(): void {
    if (!AppManager.uiState.ext_mode) {
      this.continuationClient?.close()
      this.continuationClient = undefined
      this.continuationMessageBuffer = ''
      this.continuationSocketConnected = false
      return
    }
    if (this.continuationSocketConnected) {
      return
    }
    const socketPath = AppManager.uiState.getSocketPath('easytier_vpn_socket')
    this.continuationClient?.close()
    const client = socket.constructLocalSocketInstance()
    this.continuationClient = client
    this.continuationMessageBuffer = ''
    const address: socket.LocalConnectOptions = {
      address: {
        address: socketPath
      }
    }

    const reconnect = () => {
      if (!AppManager.uiState.ext_mode || this.continuationSocketConnected) {
        return
      }
      setTimeout(() => {
        this.syncContinuationSocket()
      }, 500)
    }

    client.connect(address).then(() => {
      this.continuationSocketConnected = true
      Logger.info('Connected to continuation socket', this)
    }).catch((error: BusinessError) => {
      Logger.debug(`continuation socket retry code=${error.code} message=${error.message}`, this)
      reconnect()
    })

    client.on('message', (value: socket.LocalSocketMessageInfo) => {
      try {
        const decoded = decodeSocketChunk(this.continuationMessageBuffer, value.message)
        this.continuationMessageBuffer = decoded.rest
        for (const rawMessage of decoded.messages) {
          const msg = parseVpnBridgeMessage(rawMessage)
          if (msg.type === 'continue_state') {
            const state = msg.data as VpnContinueStateData
            if (state.active) {
              this.activateMissionContinue()
            } else {
              this.deactivateMissionContinue()
            }
          }
        }
      } catch (error) {
        Logger.error(`continuation socket message error: ${JSON.stringify(error)}`, this)
      }
    })

    client.on('close', () => {
      this.continuationSocketConnected = false
      this.continuationClient = undefined
      this.continuationMessageBuffer = ''
      this.deactivateMissionContinue()
      reconnect()
    })
  }

  startContinuousTask(cfg: string, uuid: string | undefined, name: string | undefined) {
    if (!AppManager.permission.isGetLocPerm() ||
      !canIUse("SystemCapability.ResourceSchedule.BackgroundTaskManager.ContinuousTask")) {
      if (!easytier.runNetworkInstance(cfg)) {
        sendToast("实例启动失败, 可能是内核错误, 请上报日志.", $r("sys.symbol.exclamationmark_circle"), 1)
        Logger.error("启动失败", this)
      } else {
        startRuntimeStatsRecording(this.context.filesDir)
        try {
          const config: ConfigJson = JSON.parse(cfg)
          if (config.no_tun) {
            this.activateMissionContinue()
          }
        } catch (_) {
        }
      }
      return
    }
    Logger.info("start background alive", this)
    let wantAgentInfo: wantAgent.WantAgentInfo = {
      wants: [
        {
          bundleName: "top.frankhan.easytier",
          abilityName: "EntryAbility"
        }
      ],
      actionType: wantAgent.OperationType.START_ABILITY,
      requestCode: 0,
      actionFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
    };
    let request: geoLocationManager.LocationRequest = {
      priority: geoLocationManager.LocationRequestPriority.LOW_POWER,
      timeInterval: 7200,
      distanceInterval: 10000,
      maxAccuracy: 1000
    };
    try {
      wantAgent.getWantAgent(wantAgentInfo).then((wantAgentObj: WantAgent) => {
        try {
          backgroundTaskManager.startBackgroundRunning(this.context, ["location"], wantAgentObj).then(() => {
            if (AppManager.uiState.inittedGitCore?easytier.runNetworkInstance(cfg):easytier_release.runNetworkInstance(cfg)) {
              startRuntimeStatsRecording(this.context.filesDir)
              try {
                const config: ConfigJson = JSON.parse(cfg)
                if (config.no_tun) {
                  this.activateMissionContinue()
                }
              } catch (_) {
              }
              setTimeout(() => {
                updateFavorite()
                publishTextNotification(name ?? "N/A")
              }, 300)
              if (uuid) {
                HMRouterMgr.to('StatusPage')
                  .withParam(uuid)
                  .withAnimator(new BottomAnimator())
                  .pushAsync()
              }
              geoLocationManager.on('locationChange', request, () => {});
            } else {
              sendToast("实例启动失败, 可能是内核错误, 请上报日志.", $r("sys.symbol.exclamationmark_circle"), 1)
              Logger.error("启动失败", this)
              this.stopContinuousTask()
            }
          }).catch((err: BusinessError) => {
            Logger.error(`startBackgroundRunning failed: ${err.code}, ${err.message}`, this)
          });
        } catch (error) {
          Logger.error(`startBackgroundRunning error: ${JSON.stringify(error)}`, this)
        }
      }).catch((err: BusinessError) => {
        Logger.error(`getWantAgent failed: ${err.code}, ${err.message}`, this)
      });
    } catch (error) {
      Logger.error(`getWantAgent error: ${JSON.stringify(error)}`, this)
    }
  }

  stopContinuousTask() {
    this.deactivateMissionContinue();
    stopRuntimeStatsRecording()
    if (!canIUse("SystemCapability.ResourceSchedule.BackgroundTaskManager.ContinuousTask")) {
      return;
    }
    Logger.info("stop background alive", this)
    try {
      geoLocationManager.off("locationChange")
    } catch (error) {
      Logger.error(`off locationChange error: ${JSON.stringify(error)}`, this)
    }
    const destroyVpn = () => {
      if (this.vpnConnection) {
        this.vpnConnection.destroy().then(() => {
          Logger.info("vpnConnection destroyed", this)
          this.vpnConnection = undefined
        }).catch((err: BusinessError) => {
          Logger.error(`vpnConnection destroy failed: ${err.code}, ${err.message}`, this)
        })
      }
    }
    backgroundTaskManager.stopBackgroundRunning(this.context).catch((err: BusinessError) => {
      Logger.error(`stopBackgroundRunning failed: ${err.code}, ${err.message}`, this)
    }).finally(() => {
      destroyVpn()
      cancelNotification()
    });
  }

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam) {
    this.deactivateMissionContinue();
    RemoteManageService.setHostHandlerProvider(() => this.createRemoteHostHandler())
    this.listenCardCall()
    CrashLogService.init(this.context.filesDir)
    easytier.initLogManager(this.context.filesDir, 'ui')
    easytier.configureLogManager(false, false)
    EventHelper.emitterListener("entry_sync_continuation_socket", this.entrySyncContinuationSocketCallback)
    HMRouterMgr.openLog("INFO")
    HMRouterMgr.init({
      context: this.context
    })
    Logger.info("BuildTime:" + BUILD_TIME, this)
    this.start_bg_Listener()
    this.stop_bg_Listener()
    this.setup_tun_Listener()
    WindowUtil.colorMode = this.context.config.colorMode ?? -1
    this.appReadyPromise = this.initApp()
    this.appReadyPromise.then(() => {
      this.readSharedData(want)
      if (launchParam.launchReason === AbilityConstant.LaunchReason.CONTINUATION) {
        if (want.parameters !== undefined) {
          let url = want.parameters.data as string
          this.readUri(url)
        }
      }
      if (AppManager.uiState.inittedGitCore) {
        easytier.initPanicHook()
      }else {
        easytier_release.initPanicHook()
      }
    })
  }

  onCollaborate(wantParam: Record<string, Object>): AbilityConstant.CollaborateResult {
    Logger.info("onCollaborate", this)
    const result = RemoteManageService.handleCollaborate(this.context, wantParam)
    return result === 0 ? AbilityConstant.CollaborateResult.ACCEPT : AbilityConstant.CollaborateResult.REJECT
  }

  private createRemoteHostHandler(): RemoteHostHandler {
    return new EntryRemoteHostHandler(this)
  }

  remoteWaitReady(): Promise<void> {
    return this.appReadyPromise
  }

  remoteManageConnected(): void {
    if (this.remoteManageSnapshotSessionCount === 0) {
      try {
        AppManager.easytier.requestRuntimeSnapshotSubscription(true)
      } catch (_) {
      }
    }
    this.remoteManageSnapshotSessionCount += 1
  }

  remoteManageDisconnected(): void {
    if (this.remoteManageSnapshotSessionCount <= 0) {
      return
    }
    this.remoteManageSnapshotSessionCount -= 1
    if (this.remoteManageSnapshotSessionCount === 0) {
      try {
        AppManager.easytier.requestRuntimeSnapshotSubscription(false)
      } catch (_) {
      }
    }
  }

  private remoteSafeUUID(): string {
    let uuid = util.generateRandomUUID()
    while (easytier.getConfig(uuid)) {
      uuid = util.generateRandomUUID()
    }
    return uuid
  }

  private remotePublishConfigChanged(): void {
    AppManager.data.refreshConfigIds()
    EventHelper.emitterPublish(CLOUD_CONFIG_CHANGED_EVENT)
    updateFavorite()
    RemoteManageService.notifyHostSummaryDirty()
  }

  remoteConfigList(): RemoteConfigMeta[] {
    try {
      const entries = JSON.parse(easytier.listConfigs()) as RemoteConfigMeta[]
      return (entries ?? []).map((entry) => {
        const configId = entry.configId
        const displayName = entry.displayName ?? configId
        return {
          configId,
          displayName,
          favorite: entry.favorite,
          running: AppManager.easytier.isRunning(configId)
        } as RemoteConfigMeta
      }).filter((entry) => entry.configId.length > 0)
    } catch (_) {
      return []
    }
  }

  private runtimeDisplayName(instance: RuntimeInstanceState): string {
    const configId = instance.configId
    const instanceId = instance.instanceId
    if (instance.displayName && instance.displayName.length > 0 &&
      instance.displayName !== configId && instance.displayName !== instanceId) {
      return instance.displayName
    }
    return AppManager.easytier.getConfigName(configId) ?? AppManager.easytier.getConfigName(instanceId) ?? '未命名实例'
  }

  private runtimeLite(instance: RuntimeInstanceState): RemoteRuntimeInstanceLite {
    return {
      configId: instance.configId,
      instanceId: instance.instanceId,
      displayName: this.runtimeDisplayName(instance),
      running: instance.running,
      myNodeInfo: instance.myNodeInfo,
      peerCount: instance.peers?.length ?? 0,
      routeCount: instance.routes?.length ?? 0
    }
  }

  remoteRuntimeSummary(): RemoteRuntimeSummary {
    const configs = this.remoteConfigList()
    const runningConfigs = AppManager.easytier.getRunningInstances()
    return {
      configCount: configs.length,
      runningCount: runningConfigs.length,
      runningConfigs: runningConfigs.map((instance) => this.runtimeLite(instance)),
      runtimeDurationText: AppManager.runtimeStats.runtimeDurationText,
      memoryUsageText: AppManager.runtimeStats.memoryUsageText
    }
  }

  remoteSettings(): RemoteSettingsState {
    return {
      ext_mode: AppManager.uiState.ext_mode,
      dev: AppManager.uiState.dev,
      vpn_routes: AppManager.uiState.vpn_routes,
      force_global: AppManager.uiState.force_global,
      dns: AppManager.uiState.dns,
      core_log: AppManager.uiState.core_log,
      debug_log: AppManager.uiState.debug_log,
      distributePerm: AppManager.permission.isGetDistributePerm(),
      locPerm: AppManager.permission.isGetLocPerm(),
      notificationPerm: AppManager.permission.isGetNotificationPerm()
    }
  }

  remoteSummary(): RemoteSummary {
    AppManager.easytier.syncRuntimeSnapshotFromNative()
    return {
	      appVersion: APP_VERSION,
	      coreVersion: CORE_VERSION,
	      deviceName: deviceInfo.productModel,
	      sdkApiVersion: deviceInfo.sdkApiVersion,
	      configs: this.remoteConfigList(),
	      runtime: this.remoteRuntimeSummary(),
	      settings: this.remoteSettings()
    }
  }

  remoteGetConfig(configId: string): RemoteGetConfigResult | undefined {
    if (!configId) {
      return undefined
    }
    const raw = easytier.getConfig(configId)
    if (!raw) {
      return undefined
    }
    try {
      const rawText: string = raw as string
      const config: ConfigJson = JSON.parse(rawText) as ConfigJson
      return {
        configId,
        displayName: easytier.getConfigDisplayNameById(configId) ?? configId,
        config
      }
    } catch (_) {
      return undefined
    }
  }

  remoteGetRuntimeInstance(configId: string): RuntimeInstanceState | undefined {
    if (!configId) {
      return undefined
    }
    const instance = AppManager.easytier.getRunningInstance(configId)
    if (!instance) {
      return undefined
    }
    return {
      configId: instance.configId,
      instanceId: instance.instanceId,
      displayName: this.runtimeDisplayName(instance),
      running: instance.running,
      tunRequired: instance.tunRequired,
      tunAttached: instance.tunAttached,
      magicDnsEnabled: instance.magicDnsEnabled,
      needExitNode: instance.needExitNode,
      myNodeInfo: instance.myNodeInfo,
      routes: instance.routes ?? [],
      peers: instance.peers ?? []
    }
  }

  remoteGetConfigFields(configId: string, fields: string[]): RemoteGetFieldsResult {
    return {
      values: fields.map((field) => {
        const rawValue = easytier.getConfigField(configId, field)
        const result: RemoteFieldValueResult = {
          field,
          rawValue: rawValue ?? undefined,
          found: rawValue !== null && rawValue !== undefined
        }
        return result
      })
    }
  }

  remoteSetConfigField(configId: string, field: string, value: ConfigFieldValue): boolean {
    if (!configId || !field) {
      return false
    }
    const ok = easytier.setConfigField(configId, field, JSON.stringify(value ?? null))
    if (ok) {
      this.remotePublishConfigChanged()
    }
    return ok
  }

  remoteSaveConfig(configId: string, displayName: string, config: ConfigJson): boolean {
    if (!configId || !config) {
      return false
    }
    const ok = easytier.saveConfig(configId, displayName || configId, JSON.stringify(config))
    if (ok) {
      this.remotePublishConfigChanged()
    }
    return ok
  }

  remoteCreateDefaultConfig(displayName: string): RemoteCreateDefaultConfigResult | undefined {
    const config: ConfigJson = getDefaultConfig(getHostname())
    const configId = this.remoteSafeUUID()
    config.instance_id = configId
    const name = displayName && displayName.length > 0 ? displayName : 'EasyTier'
    if (!this.remoteSaveConfig(configId, name, config)) {
      return undefined
    }
    return { configId, displayName: name, config }
  }

  remoteImportConfig(config: ConfigJson, displayName: string): RemoteCreateDefaultConfigResult | undefined {
    try {
      const configText: string = JSON.stringify(config)
      const imported: ConfigJson = JSON.parse(configText) as ConfigJson
      const configId = this.remoteSafeUUID()
      imported.instance_id = configId
      const name = displayName && displayName.length > 0 ? displayName : configId
      if (!this.remoteSaveConfig(configId, name, imported)) {
        return undefined
      }
      return { configId, displayName: name, config: imported }
    } catch (_) {
      return undefined
    }
  }

  remoteDeleteConfig(configId: string): boolean {
    const ok = AppManager.data.delConfig(configId)
    if (ok) {
      this.remotePublishConfigChanged()
    }
    return ok
  }

  remoteRenameConfig(configId: string, displayName: string): boolean {
    if (!configId || !displayName) {
      return false
    }
    const ok = easytier.renameStoredConfig(configId, displayName)
    if (ok) {
      this.remotePublishConfigChanged()
    }
    return ok
  }

  remoteSetSetting(key: string, value: boolean | string): RemoteSettingsState {
    switch (key) {
      case 'ext_mode':
        if (AppManager.easytier.runningNetworks.size === 0) {
          AppManager.uiState.ext_mode = Boolean(value)
        }
        break
      case 'dev':
        AppManager.uiState.dev = Boolean(value)
        break
      case 'vpn_routes':
        AppManager.uiState.vpn_routes = Boolean(value)
        break
      case 'force_global':
        AppManager.uiState.force_global = Boolean(value)
        break
      case 'core_log':
        AppManager.uiState.core_log = Boolean(value)
        break
      case 'debug_log':
        AppManager.uiState.debug_log = Boolean(value)
        break
      case 'dns':
        if (typeof value === 'string') {
          AppManager.uiState.dns = value
        }
        break
    }
    return this.remoteSettings()
  }

  async remoteRequestPermission(kind: string): Promise<RemoteSettingsState> {
    if (kind === 'distributed') {
      await AppManager.permission.requestDistributePerm()
    } else if (kind === 'location') {
      await AppManager.permission.requestLocPerm()
    } else if (kind === 'notification') {
      await AppManager.permission.requestNotificationPerm()
    }
    await AppManager.permission.updatePermStatus()
    return this.remoteSettings()
  }

  async initApp() {
    AppManager.uiState.init()
    AppManager.uiState.setSocketFilesDir(this.context.filesDir)
    try {
      await AppManager.preference.init(this.context)
    } catch (error) {
      Logger.error(`PreferenceUtil failed to init.\n${error}`, AppManager)
      return
    }
    if (AppManager.uiState.debug_log) {
      MemoryDiagnosticsService.enableSystemLeakWatcher(true)
      MemoryDiagnosticsService.markDelayed('EntryAbility.preference.init')
    }
    await AppManager.data.init()
    if (AppManager.uiState.debug_log) {
      MemoryDiagnosticsService.markDelayed('EntryAbility.data.init')
    }
    if (deviceInfo.productModel !== "emulator") {
      AppManager.easytier.init()
    }
    if (AppManager.uiState.debug_log) {
      MemoryDiagnosticsService.markDelayed('EntryAbility.easytier.init')
    }
    this.syncContinuationSocket()
  }

  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam) {
    Logger.debug("onNetWant", this)
    this.readSharedData(want)
    updateFavorite()
    if (launchParam.launchReason === AbilityConstant.LaunchReason.CONTINUATION) {
      if (want.parameters !== undefined) {
        let url = want.parameters.data as string
        this.readUri(url)
      }
    }
  }

  listenCardCall() {
    this.callee.on("send_card_id", (indata: rpc.MessageSequence) => {
      try {
        const obj = JSON.parse(indata.readString()) as object
        const formId = obj['formId'] as string
        AppManager.preference.addCardId(formId)
      } catch (error) {
        Logger.error(`send_card_id parse error: ${JSON.stringify(error)}`, this)
      }
      return null
    })
    this.callee.on("start_favorite", () => {
      if (AppManager.uiState.favorite) {
        if (AppManager.easytier.isFavoritesRunning()) {
          AppManager.easytier.stop()
        } else {
          if (AppManager.easytier.runningNetworks.size > 0) {
            AppManager.easytier.stop()
          }
          AppManager.easytier.start(AppManager.uiState.favorite, true)
        }
      }
      return null
    })
  }

  readUri(uri: string | undefined) {
    Logger.info("get uri:" + uri, this)
    try {
      let urlObject = url.URL.parseURL(uri);
      unwrapUrl(urlObject)
    } catch (err) {
      let error = err as BusinessError;
      Logger.error(`readUri error, code: ${error.code}, mesage: ${error.message}`, this);
    }
  }

  async readSharedData(want: Want) {
    let uri = want.uri;
    if (uri && uri.length > 0) {
      this.readUri(uri)
    } else {
      systemShare.getSharedData(want)
        .then((data: systemShare.SharedData) => {
          data?.getRecords()?.forEach(async (record: systemShare.SharedRecord) => {
            if (record.uri && record.uri.length > 0) {
              Logger.debug("read shared file: " + JSON.stringify(record), this)
              try {
                let cfg = ""
                try {
                  cfg = fs.readTextSync(new fileUri.FileUri(record.uri).path)
                } catch (e) {
                   Logger.error("fs read error: " + JSON.stringify(e), this)
                }
                if (cfg) {
                  AppManager.data.importToml(cfg)
                }
              } catch (error) {
                Logger.debug("read file error: " + JSON.stringify(error), this)
              }
            } else if (record.content && record.content.length > 0) {
              let urlObject = url.URL.parseURL(record.content);
              let hostname = urlObject.hostname
              switch (hostname) {
                case "appgallery.huawei.com": {
                  let app = urlObject.params.get("id")
                  Logger.debug("get AppId: " + app, this)
                  AppManager.web.getAppInfo(app!, (name, icon) => {
                    AppManager.preference.setAppInfo(app!, name, icon)
                  })
                  break;
                }
                case "easytier.cn": {
                  unwrapUrl(urlObject)
                  break;
                }
              }
            }
          })
        })
    }
  }

  onDestroy() {
	    Logger.debug("onDestroy", this)
	    MemoryDiagnosticsService.enableSystemLeakWatcher(false)
	    RemoteManageService.destroyHostSessions()
	    AppManager.easytier.destroy()
    this.stopContinuousTask()
    this.kernelClient?.close()
    this.continuationClient?.close()
    EventHelper.emitterOff("entry_sync_continuation_socket", this.entrySyncContinuationSocketCallback)
    EventHelper.emitterOff("start_bg", this.startBgCallback)
    EventHelper.emitterOff("stop_bg", this.stopBgCallback)
    EventHelper.emitterOff("setup_tun", this.setupTunCallback)
    EventHelper.emitterOff("change_ipv4", this.changeIpv4Callback)
    this.callee.off("send_card_id")
    this.callee.off("start_favorite")
  }

  async onContinue(wantParam: Record<string, Object>): Promise<AbilityConstant.OnContinueResult> {
    if (AppManager.easytier.runningNetworks.size > 0) {
      let uuid = AppManager.easytier.runningNetworks.keys().next().value as string
      let cfg: ConfigJson | undefined = AppManager.easytier.getConfig(uuid)
      Logger.debug("find "+JSON.stringify(cfg))
      if (cfg) {
        wantParam['data'] = await buildShareUrlSync(cfg, true)
        wantParam[wantConstant.Params.SUPPORT_CONTINUE_SOURCE_EXIT_KEY] = false;
        AppManager.easytier.stop()
        return AbilityConstant.OnContinueResult.AGREE;
      }else {
        return AbilityConstant.OnContinueResult.MISMATCH;
      }
    }else {
      return AbilityConstant.OnContinueResult.MISMATCH;
    }
  }

  start_bg_Listener() {
    Logger.debug("start_bg_Listener", this)
    EventHelper.emitterListener("start_bg", this.startBgCallback)
  }

  stop_bg_Listener() {
    Logger.debug("stop_bg_Listener", this)
    EventHelper.emitterListener("stop_bg", this.stopBgCallback)
  }

  setup_tun_Listener() {
    Logger.debug("setup_tun_Listener", this)
    EventHelper.emitterListener("setup_tun", this.setupTunCallback)
    EventHelper.emitterListener("change_ipv4", this.changeIpv4Callback)
  }

  safeDns(): string {
    if (isIpAddr(AppManager.uiState.dns)) {
      return AppManager.uiState.dns
    } else {
      return "223.5.5.5"
    }
  }

  async setup_tun(ip: string, mask: number, magicDNS: boolean, inst_id: string, needExitNode: boolean, routes?: string[]) {
    Logger.info(`setup_tun start instance=${inst_id} ip=${ip}/${mask} magicDNS=${magicDNS} needExitNode=${needExitNode}`, this)
    Logger.debug("当前IP:" + ip, this)
    Logger.info(`setup_tun routes kernel=${JSON.stringify(routes ?? [])}`, this)
    let appList = [
      deviceInfo.sdkApiVersion >= 22? "":"top.frankhan.easytier",
      ...AppManager.preference.getBlackList()
    ]
    let vpnConfig: vpnExtension.VpnConfig = {
      addresses: [
        {
          address: {
            address: ip,
            family: 1,
          },
          prefixLength: mask
        }
      ],
      blockedApplications: AppManager.uiState.white_list?[]:appList,
      trustedApplications: AppManager.uiState.white_list?appList:[],
      dnsAddresses: magicDNS ? ["100.100.100.101"] : (AppManager.uiState.dev ? [this.safeDns()] : ["223.5.5.5"]),
      mtu: 1380,
      routes: AppManager.preference.getVpnCfgRoutes(ip, magicDNS, needExitNode, routes)
    }
    Logger.info(`setup_tun finalVpnRoutes=${JSON.stringify(vpnConfig.routes ?? [])}`, this)
    if (this.vpnConnection === undefined) {
      Logger.error("vpnConnection not found", this)
      return
    }
    await this.vpnConnection.destroy()
    Logger.debug("VPN配置:" + JSON.stringify(vpnConfig), this)
    this.vpnConnection.create(vpnConfig).then((fd) => {
      Logger.info(`vpnConnection.create success instance=${inst_id} fd=${fd}`, this)
      this.activateMissionContinue()
      if (AppManager.uiState.inittedGitCore) {
        easytier.setTunFd(inst_id, fd)
        Logger.info(`setTunFd sent to git_core instance=${inst_id}`, this)
      }else {
        easytier_release.setTunFd(inst_id, fd)
        Logger.info(`setTunFd sent to release instance=${inst_id}`, this)
      }
    }).catch((error: BusinessError) => {
      Logger.error(`vpnConnection create failed: ${error.code}, ${error.message}`, this)
    })
  }

  prepare_vpn(shouldProtect: boolean = false, callback: () => void = () => {}) {
    if (this.vpnConnection !== undefined) {
      Logger.info("prepare_vpn reuse existing vpnConnection", this)
      if (shouldProtect) {
        this.vpnConnection.protectProcessNet().then(() => {
          Logger.info("protectProcessNet completed before kernel start", this)
          callback()
        }).catch((error: BusinessError) => {
          Logger.error(`protectProcessNet failed: ${error.code}, ${error.message}`, this)
          callback()
        })
        return
      }
      callback()
      return;
    }
    Logger.info("prepare vpn", this)
    AppManager.permission.requestVpnPerm(async () => {
      this.vpnConnection = vpnExtension.createVpnConnection(getContext(this) as vpnExtension.VpnExtensionContext)
      Logger.info("vpnConnection created in prepare_vpn", this)
      if (shouldProtect) {
        await this.vpnConnection.protectProcessNet()
        Logger.info("protectProcessNet completed before kernel start", this)
      }
      callback()
    })
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    try {
      windowStage.getMainWindowSync().on('windowSizeChange', (data) => {
        WindowUtil.update(data.width, data.height)
      });
      windowStage.getMainWindowSync().on('avoidAreaChange', (data) => {
        if (data.type == window.AvoidAreaType.TYPE_SYSTEM) {
          WindowUtil.setStatusBarHeight = data.area.topRect.height
        } else if (data.type == window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR) {
          WindowUtil.setNavigationBarHeight = data.area.bottomRect.height
        }
      })
    } catch (error) {
    }
    windowStage.loadContent('pages/HMRouterIndex', (err) => {
      if (err.code) {
        Logger.error('Failed to load the content. Cause: ' + JSON.stringify(err), this);
        return;
      }
    });
  }

  onWindowStageDestroy(): void {
    WindowUtil.windowStageDestroy()
  }

  onForeground(): void {
    WindowUtil.foreground()
    AppManager.easytier.setRuntimeSnapshotForeground(true)
    this.syncContinuationSocket()
  }

  onBackground(): void {
    WindowUtil.background()
    AppManager.easytier.setRuntimeSnapshotForeground(false)
  }

  onConfigurationUpdate(newConfig: Configuration): void {
    WindowUtil.colorMode = newConfig.colorMode ?? -1
    EventHelper.emitterPublish("update_color_mode")
  }

  private connectToKernelSocket(socketPath: string) {
    if (this.kernelSocketConnected) {
      return
    }
    this.kernelClient?.close()
    this.kernelClient = socket.constructLocalSocketInstance()
    this.kernelMessageBuffer = ''
    const address: socket.LocalConnectOptions = {
      address: {
        address: socketPath
      }
    }

    let retryCount = 0
    const connect = () => {
      if (AppManager.uiState.ext_mode) {
        return
      }
      this.kernelClient?.connect(address).then(() => {
        this.kernelSocketConnected = true
        Logger.info("Connected to kernel socket", this)
      }).catch((error: BusinessError) => {
        if (error.code === 2301106) {
          this.kernelSocketConnected = true
          return
        }
        Logger.info(`kernel socket connect retry=${retryCount} code=${error.code} message=${error.message}`, this)
        if (retryCount < 20 && !AppManager.uiState.ext_mode) {
          retryCount++
          setTimeout(connect, 500)
        }
      })
    }
    setTimeout(connect, 200)

    this.kernelClient.on('message', (value: socket.LocalSocketMessageInfo) => {
      try {
        const decoded = decodeSocketChunk(this.kernelMessageBuffer, value.message)
        this.kernelMessageBuffer = decoded.rest
        for (const rawMessage of decoded.messages) {
          const msg = parseKernelSocketMessage(rawMessage)
          if (msg.messageType === 'runtime_snapshot') {
            const snapshot = typeof msg.payloadJson === 'string' ? JSON.parse(msg.payloadJson) as RuntimeAggregateState : msg.payloadJson as RuntimeAggregateState
            EventHelper.emitterPublish("kernel_runtime_snapshot", {
              data: {
                snapshot
              }
            })
          } else if (msg.messageType === 'tun_request') {
            const payload = typeof msg.payloadJson === 'string' ? JSON.parse(msg.payloadJson) as TunRequestPayload : msg.payloadJson as TunRequestPayload
            const cidr = payload.virtualIpv4Cidr ?? ''
            const ip = payload.virtualIpv4 ?? cidr.split('/')[0]
            const mask = Number(cidr.split('/')[1] ?? '24')
            const routes = payload.aggregatedRoutes ?? []
            this.setup_tun(ip, mask, payload.magicDnsEnabled, payload.instanceId, payload.needExitNode, routes)
          }
        }
      } catch (e) {
        Logger.error("kernel socket message error: " + JSON.stringify(e), this)
      }
    })

    this.kernelClient.on('close', () => {
      this.kernelSocketConnected = false
    })
  }
}
