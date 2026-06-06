import easytier from 'easytier-ohrs'
import { EventHelper } from './util/EventHelper'
import { AppManager } from './AppManager'
import { Logger, LogLocate } from './shared/logging/Logger'
import { sendToast } from './ToastUtil'
import { InstanceInfo } from './class/InstanceInfo'
import { emitter } from '@kit.BasicServicesKit'
import { getDefaultConfig } from './config/defaults/ConfigDefaults'
import { JSON } from '@kit.ArkTS'
import { LogDataSource } from './class/data_source/LogDataSource'
import { updateFavorite } from './services/form/CommunicationUtil'
import { HMRouterMgr } from '@hadss/hmrouter'
import { updateTextNotification } from './util/NoticeHelper'
import { fileIo, fileUri } from '@kit.CoreFileKit'
import { systemShare } from '@kit.ShareKit'
import { common, Want } from '@kit.AbilityKit'
import { uniformTypeDescriptor } from '@kit.ArkData'
import { socket, vpnExtension } from '@kit.NetworkKit'
import { syncWholeConfig } from './ConfigSyncUtil'
import { ConfigJson } from './config/schema/SchemaConfig'
import { RuntimeAggregateState, RuntimeInstanceState } from './types/runtime/RuntimeTypes'
import { VpnLogData } from './infrastructure/bridge/kernel/KernelBridgeTypes'
import { routeSignature } from './infrastructure/bridge/kernel/RouteStore'
import { getEditingConfig as getEditingStoredConfig, getStoredConfig, getStoredConfigLabel, getStoredConfigName, listStoredConfigs as listStoredConfigEntries, StoredConfigMetaLite } from './services/config/storage/StoredConfigService'
import { connectVpnExtensionSocket } from './infrastructure/bridge/kernel/VpnExtensionSocketBridge'
import { orchestrateInstanceStart } from './services/easytier/runtime/StartOrchestrationService'
import { getHostname } from './util/Conversion'
import { CrashLogService } from './services/crash/CrashLogService'


@LogLocate("EasyTierUtil")
@ObservedV2
export class EasyTierUtil {
  @Trace appLogs: LogDataSource = new LogDataSource
  @Trace runningNetworks: Map<string, RuntimeInstanceState> = new Map()
  @Trace instanceInfos: Map<string, InstanceInfo> = new Map()
  @Trace needTUN: Set<string> = new Set()
  @Trace temporaryConfigIds: Set<string> = new Set()
  private logTimer: number | undefined
  client: socket.LocalSocket | undefined
  vpnMessageBuffer: string = ''
  private isVpnConnected: boolean = false
  private runtimeSnapshotSubscriptionCount: number = 0
  private runtimeSnapshotSubscribed: boolean = false
  private runtimeSnapshotForeground: boolean = true
  private initialized: boolean = false
  private kernelRuntimeSnapshotCallback: Callback<emitter.EventData> = (event: emitter.EventData) => {
    if (event?.data?.snapshot) {
      this.processRuntimeSnapshot(event.data.snapshot as RuntimeAggregateState, false)
    }
  }

  init() {
    if (this.initialized) {
      return
    }
    this.initialized = true
    EventHelper.emitterListener("kernel_runtime_snapshot", this.kernelRuntimeSnapshotCallback)

    this.logTimer = setInterval(() => {
      this.processLogs(easytier.drainLogLines())
    }, 500)

    if (AppManager.uiState.ext_mode) {
      this.connectToVpnExtension("easytier_vpn_socket")
    }
  }

  destroy() {
    if (!this.initialized) {
      return
    }
    this.initialized = false
    EventHelper.emitterOff("kernel_runtime_snapshot", this.kernelRuntimeSnapshotCallback)
    if (this.logTimer !== undefined) {
      clearInterval(this.logTimer)
      this.logTimer = undefined
    }
    this.client?.close()
    this.client = undefined
  }

  version() {
    return easytier.easytierVersion()
  }

  convertToml2NetworkConfig(toml: string): string {
    return easytier.convertTomlToNetworkConfig(toml)
  }

  private updateNotification(uuid: string) {
    let info = AppManager.easytier.instanceInfos.get(uuid)
    if (info) {
      updateTextNotification(this.getConfigName(uuid) ?? "N/A", info)
    }
  }

  private getValidInstanceId(instance: RuntimeInstanceState): string | undefined {
    const instanceId = instance.instanceId
    if (typeof instanceId !== 'string' || instanceId.length === 0) {
      return undefined
    }
    return instanceId
  }

  private processRuntimeSnapshot(snapshot: RuntimeAggregateState, fromVpn: boolean = true): void {
    if (!fromVpn && AppManager.uiState.ext_mode && this.isVpnConnected) {
      return
    }

    const instances = snapshot.instances ?? []
    const activeIds = new Set<string>()
    instances.forEach((instance) => {
      const instanceId = this.getValidInstanceId(instance)
      if (!instanceId) {
        Logger.error(`processRuntimeSnapshot skip invalid instanceId: ${JSON.stringify(instance)}`, this)
        return
      }
      activeIds.add(instanceId)
      if (!(instance.running as boolean)) {
        return
      }
      this.runningNetworks.set(instanceId, instance)
      if (!this.instanceInfos.has(instanceId)) {
        this.instanceInfos.set(instanceId, new InstanceInfo())
      }
      this.instanceInfos.get(instanceId)!.update(instance)
      this.updateNotification(instanceId)
    })

    for (const uuid of Array.from(this.runningNetworks.keys())) {
      if (!activeIds.has(uuid)) {
        this.runningNetworks.delete(uuid)
        this.instanceInfos.delete(uuid)
        this.needTUN.delete(uuid)
      }
    }

  }

  private markOptimisticRunning(config: ConfigJson, displayName: string): void {
    const instanceId = config.instance_id as string | undefined
    if (!instanceId) {
      return
    }
    const networkLength = Number(config.network_length ?? 24)
    const virtualIpv4 = typeof config.virtual_ipv4 === 'string' ? config.virtual_ipv4 as string : undefined
    const state: RuntimeInstanceState = {
      configId: instanceId,
      instanceId,
      displayName,
      running: true,
      tunRequired: !Boolean(config.no_tun),
      tunAttached: false,
      magicDnsEnabled: Boolean(config.enable_magic_dns),
      needExitNode: Array.isArray(config.exit_nodes) && config.exit_nodes.length > 0,
      myNodeInfo: {
        virtualIpv4,
        virtualIpv4Cidr: virtualIpv4 ? `${virtualIpv4}/${networkLength}` : undefined,
      },
      routes: [],
      peers: []
    }
    this.runningNetworks.set(instanceId, state)
    if (!this.instanceInfos.has(instanceId)) {
      this.instanceInfos.set(instanceId, new InstanceInfo())
    }
    this.instanceInfos.get(instanceId)!.update(state)
  }

  processLogs(logs: string[]) {
    logs.forEach((value) => {
      this.appLogs.add(value)
    })
  }

  private connectToVpnExtension(socketName: string) {
    this.client = connectVpnExtensionSocket(socketName, this.client, {
      isExtMode: () => AppManager.uiState.ext_mode,
      getSocketPath: (name: string) => AppManager.uiState.getSocketPath(name),
      onConnected: () => {
        this.isVpnConnected = true
        this.sendRuntimeSnapshotSubscription()
      },
      onDisconnected: () => {
        this.isVpnConnected = false
      },
      onSnapshot: (snapshot: RuntimeAggregateState) => {
        Logger.debug(`VpnExtension runtime_snapshot received instances=${snapshot.instances?.length ?? 0}`, this)
        this.processRuntimeSnapshot(snapshot, true)
      },
      onLogs: (logData: VpnLogData) => {
        this.processLogs(logData.logs)
      }
    })
  }

  public requestRuntimeSnapshotSubscription(enabled: boolean): void {
    if (enabled) {
      this.runtimeSnapshotSubscriptionCount += 1
    } else {
      this.runtimeSnapshotSubscriptionCount = Math.max(0, this.runtimeSnapshotSubscriptionCount - 1)
    }
    this.updateRuntimeSnapshotSubscription(enabled)
  }

  public setRuntimeSnapshotForeground(active: boolean): void {
    if (this.runtimeSnapshotForeground === active) {
      return
    }
    this.runtimeSnapshotForeground = active
    this.updateRuntimeSnapshotSubscription(false)
  }

  private updateRuntimeSnapshotSubscription(forceResend: boolean): void {
    const shouldSubscribe = this.runtimeSnapshotSubscriptionCount > 0 && this.runtimeSnapshotForeground
    if (shouldSubscribe === this.runtimeSnapshotSubscribed) {
      if (forceResend && shouldSubscribe) {
        this.sendRuntimeSnapshotSubscription()
      }
      return
    }
    this.runtimeSnapshotSubscribed = shouldSubscribe
    this.sendRuntimeSnapshotSubscription()
  }

  private sendRuntimeSnapshotSubscription(): void {
    if (!this.client || !this.isVpnConnected || !AppManager.uiState.ext_mode) {
      return
    }
    const rawMessage = JSON.stringify({
      type: 'snapshot_subscription',
      data: { enabled: this.runtimeSnapshotSubscribed }
    }) + '\n'
    try {
      this.client.send({ data: rawMessage }).catch((error: object) => {
        Logger.error(`send snapshot subscription failed: ${JSON.stringify(error)}`, this)
      })
    } catch (error) {
      Logger.error(`send snapshot subscription threw: ${JSON.stringify(error)}`, this)
    }
  }

  public start(uuid: string | undefined = AppManager.uiState.selected, byCard: boolean = false): boolean {
    if (uuid) {
      let config: ConfigJson | undefined = this.getConfig(uuid)
      if (config) {
        Logger.debug("start config: "+ JSON.stringify(config, undefined, 2), this)
        syncWholeConfig(uuid, this.getConfigName(uuid) ?? uuid, config)
        const started = orchestrateInstanceStart({
          config,
          name: this.getConfigName(uuid) ?? uuid,
          extMode: AppManager.uiState.ext_mode,
          socketFilesDir: AppManager.uiState.socketFilesDir,
          vpnRoutes: AppManager.uiState.vpn_routes,
          whiteList: AppManager.uiState.white_list,
          blackList: AppManager.preference.getBlackList(),
          dns: AppManager.uiState.dns,
          dev: AppManager.uiState.dev,
          forceGlobal: AppManager.uiState.force_global,
          coreLog: AppManager.uiState.core_log,
          debugLog: AppManager.uiState.debug_log,
          addNeedTun: (instanceId: string) => {
            this.needTUN.add(instanceId)
          },
          connectToVpnExtension: (socketName: string) => {
            this.connectToVpnExtension(socketName)
          },
          ensureContinuationSocket: () => {
            EventHelper.emitterPublish("entry_sync_continuation_socket")
          },
          requestVpnPerm: (callback: () => void) => {
            AppManager.permission.requestVpnPerm(callback)
          },
          requestLocPerm: () => AppManager.permission.requestLocPerm(),
          publishStartBg: (cfg: string, startId: string | undefined, startName: string) => {
            EventHelper.emitterPublish("start_bg", {
              data: {
                cfg,
                uuid: byCard ? undefined : startId,
                name: startName
              }
            })
          },
          sendInvalidConfigToast: () => {
            sendToast("非法实例, 可能是序列化错误, 请上报日志.", $r("sys.symbol.exclamationmark_circle"), 1)
          }
        })
        if (started) {
          this.markOptimisticRunning(config, this.getConfigName(uuid) ?? uuid)
          AppManager.runtimeStats.startLiveRefresh()
        }
        return started
      } else {
        return false
      }
    } else {
      return false
    }
  }

  public async temp_start(name: string, config: ConfigJson): Promise<boolean> {
    if (config) {
      await AppManager.permission.requestDistributePerm(false)
      config.hostname = getHostname()
      Logger.debug("temp start config: "+ JSON.stringify(config, undefined, 2), this)
      syncWholeConfig(config.instance_id!, name, config)
      this.temporaryConfigIds.add(config.instance_id!)
      const started = orchestrateInstanceStart({
        config,
        name,
        extMode: AppManager.uiState.ext_mode,
        socketFilesDir: AppManager.uiState.socketFilesDir,
        vpnRoutes: AppManager.uiState.vpn_routes,
        whiteList: AppManager.uiState.white_list,
        blackList: AppManager.preference.getBlackList(),
        dns: AppManager.uiState.dns,
        dev: AppManager.uiState.dev,
        forceGlobal: AppManager.uiState.force_global,
        coreLog: AppManager.uiState.core_log,
        debugLog: AppManager.uiState.debug_log,
        addNeedTun: (instanceId: string) => {
          this.needTUN.add(instanceId)
        },
        connectToVpnExtension: (socketName: string) => {
          this.connectToVpnExtension(socketName)
        },
        ensureContinuationSocket: () => {
          EventHelper.emitterPublish("entry_sync_continuation_socket")
        },
        requestVpnPerm: (callback: () => void) => {
          AppManager.permission.requestVpnPerm(callback)
        },
        requestLocPerm: () => AppManager.permission.requestLocPerm(),
        publishStartBg: (cfg: string, uuid: string | undefined, startName: string) => {
          EventHelper.emitterPublish("start_bg", {
            data: {
              cfg,
              uuid,
              name: startName
            }
          })
        },
        sendInvalidConfigToast: () => {
          sendToast("非法实例, 可能是序列化错误, 请上报日志.", $r("sys.symbol.exclamationmark_circle"), 1)
        }
      })
      if (!started) {
        AppManager.data.delConfig(config.instance_id!)
        this.temporaryConfigIds.delete(config.instance_id!)
      } else {
        this.markOptimisticRunning(config, name)
        AppManager.runtimeStats.startLiveRefresh()
      }
      return started
    } else {
      return Promise.resolve(false)
    }
  }

  public stop() {
    const temporaryRunningIds = Array.from(this.temporaryConfigIds.values())
    AppManager.runtimeStats.stopLiveRefresh()
    if (AppManager.uiState.ext_mode) {
      let want: Want = {
        bundleName: "top.frankhan.easytier",
        abilityName: "EasyTierAbility",
      }
      vpnExtension.stopVpnExtensionAbility(want)
      this.client?.close()
      this.client = undefined
      this.isVpnConnected = false
    } else {
      const runningIds = Array.from(this.runningNetworks.keys()).filter((value) => {
        return value.length > 0
      }) as string[]
      EventHelper.emitterPublish("stop_bg")
      runningIds.forEach((value) => {
        easytier.stopKernel(value)
      })
    }

    // 显式清理 UI 状态
    this.runningNetworks.clear()
    this.instanceInfos.clear()

    setTimeout(() => {
      updateFavorite()
    }, 100)
    temporaryRunningIds.forEach((configId) => {
      AppManager.data.delConfig(configId)
      this.temporaryConfigIds.delete(configId)
    })
    let stack = HMRouterMgr.getPathStack("MainNavigation")!.getAllPathName()
    if (stack[stack.length-1] == "StatusPage") {
      HMRouterMgr.pop()
    }
  }

  public isRunning(uuid?: string): boolean {
    if (uuid) {
      return this.runningNetworks.has(uuid)
    }
    return false
  }

  public getConfig(uuid: string): ConfigJson | undefined {
    return getStoredConfig(uuid)
  }

  public getEditingConfig(): ConfigJson | undefined {
    return getEditingStoredConfig(AppManager.uiState.editingInstance)
  }

  public getConfigName(uuid: string | undefined): string | undefined {
    return getStoredConfigName(uuid)
  }

  public getConfigLabel(uuid: string | undefined, emptyLabel: string = ''): string {
    return getStoredConfigLabel(uuid, emptyLabel)
  }

  public listStoredConfigs(): StoredConfigMetaLite[] {
    return listStoredConfigEntries()
  }

  public getEditingInstance() {
    return AppManager.uiState.editingInstance
  }

  public isEditingRunning(): boolean {
    return this.isRunning(this.getEditingInstance())
  }

  public isFavoritesRunning(): boolean {
    return this.isRunning(AppManager.uiState.favorite)
  }

  public writeAndShareLogs() {
    let filePath = AppManager.content.context!.filesDir + '/log.txt';
    let file: fileIo.File | null = null;
    try {
      fileIo.unlinkSync(filePath)
    }catch (_) {}
    try {
      if (!easytier.exportLogArchive(filePath)) {
        file = fileIo.openSync(filePath, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE);
        fileIo.writeSync(file.fd, this.appLogs.join2String());
        fileIo.closeSync(file);
        file = null
      }

      let shareData: systemShare.SharedData = new systemShare.SharedData({
        utd: uniformTypeDescriptor.UniformDataType.FILE,
        uri: fileUri.getUriFromPath(filePath),
        title: '分享日志'
      });
      let controller: systemShare.ShareController = new systemShare.ShareController(shareData);
      controller.show(AppManager.content.context! as common.UIAbilityContext, {
        selectionMode: systemShare.SelectionMode.SINGLE,
        previewMode: systemShare.SharePreviewMode.DEFAULT,
        excludedAbilities: [systemShare.ShareAbilityType.PRINT,
          systemShare.ShareAbilityType.SAVE_TO_SUPERHUB]
      }).catch(() => {
        Logger.error(`systemShareConfig::An unexpected error occurred.`, this);
      })
    } catch (err) {
      if (file) {
        try {
          fileIo.closeSync(file)
        } catch (_) {}
      }
      Logger.error(`日志文件写入失败. Code: ${err.code}, message: ${err.message}`, this)
    }
  }

  public writeAndShareCrashLog() {
    const context = AppManager.content.context! as common.UIAbilityContext
    const filePath = CrashLogService.getLogPath(context.filesDir)
    try {
      if (Number(fileIo.statSync(filePath).size) <= 0) {
        sendToast('暂无崩溃日志', $r('sys.symbol.doc'), 1)
        return
      }
    } catch (_) {
      sendToast('暂无崩溃日志', $r('sys.symbol.doc'), 1)
      return
    }

    try {
      let shareData: systemShare.SharedData = new systemShare.SharedData({
        utd: uniformTypeDescriptor.UniformDataType.FILE,
        uri: fileUri.getUriFromPath(filePath),
        title: '分享崩溃日志'
      });
      let controller: systemShare.ShareController = new systemShare.ShareController(shareData);
      controller.show(context, {
        selectionMode: systemShare.SelectionMode.SINGLE,
        previewMode: systemShare.SharePreviewMode.DEFAULT,
        excludedAbilities: [systemShare.ShareAbilityType.PRINT,
          systemShare.ShareAbilityType.SAVE_TO_SUPERHUB]
      }).catch(() => {
        Logger.error(`systemShareCrashLog::An unexpected error occurred.`, this);
      })
    } catch (err) {
      Logger.error(`崩溃日志分享失败. Code: ${err.code}, message: ${err.message}`, this)
    }
  }
}
