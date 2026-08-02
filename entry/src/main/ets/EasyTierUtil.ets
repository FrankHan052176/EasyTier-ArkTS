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
import { HMRouterMgr } from '@hadss/hmrouter'
import { syncWholeConfig } from './ConfigSyncUtil'
import { ConfigJson } from './config/schema/SchemaConfig'
import { RuntimeAggregateState, RuntimeInstanceState } from './types/runtime/RuntimeTypes'
import {
  RuntimePeerEventPayload,
  TrafficStatsPayload,
  VpnLogData,
  VpnRuntimeCommandData,
  VpnRuntimeCommandResultData,
  VpnRuntimeStatusData
} from './infrastructure/bridge/kernel/KernelBridgeTypes'
import { getEditingConfig as getEditingStoredConfig, getStoredConfig, getStoredConfigLabel, getStoredConfigName, listStoredConfigs as listStoredConfigEntries, StoredConfigMetaLite } from './services/config/storage/StoredConfigService'
import { orchestrateInstanceStart } from './services/easytier/runtime/StartOrchestrationService'
import { getHostname } from './util/Conversion'
import { LogFileEntry } from './types/logging/LogFileTypes'
import { LogCenterService } from './services/logging/LogCenterService'
import { findRunningInstance, listRunningInstances } from './services/runtime/RuntimeStateReducer'
import { FavoriteCardSignatureState } from './services/runtime/RuntimeNotificationService'
import { RuntimeStateCoordinator } from './services/runtime/RuntimeStateCoordinator'
import { VpnExtensionAbilityController } from './services/runtime/VpnExtensionAbilityController'
import { VpnExtensionRuntimeClient } from './services/runtime/VpnExtensionRuntimeClient'
import { requestEntryKeepAliveStart, requestEntryKeepAliveStop } from './services/runtime/EntryKeepAliveBridge'
import { VPN_EXTENSION_SOCKET_NAME } from './services/runtime/AbilityRuntimePolicy'
import { NetworkRestartResult } from './services/runtime/NetworkChangeWatchdog'
import {
  ENTRY_SYNC_CONTINUATION_SOCKET_EVENT,
  KERNEL_RUNTIME_PEER_EVENT,
  KERNEL_RUNTIME_TOPOLOGY_EVENT,
  KERNEL_TRAFFIC_STATS_EVENT
} from './types/events/RuntimeEventTypes'

@LogLocate("EasyTierUtil")
@ObservedV2
export class EasyTierUtil {
  @Trace appLogs: LogDataSource = new LogDataSource
  @Trace runningNetworks: Map<string, RuntimeInstanceState> = new Map()
  @Trace instanceInfos: Map<string, InstanceInfo> = new Map()
  @Trace needTUN: Set<string> = new Set()
  @Trace temporaryConfigIds: Set<string> = new Set()
  private logTimer: number | undefined
  private operationQueue: Promise<void> = Promise.resolve()
  private runtimeIntentGeneration: number = 0
  private pendingStartIds: Set<string> = new Set()
  private pendingStopIds: Set<string> = new Set()
  private acceptedRuntimeIds: Set<string> = new Set()
  private runtimeCommandResults: Map<string, VpnRuntimeCommandResultData> = new Map()
  private runtimeStatus: VpnRuntimeStatusData | undefined = undefined
  private vpnExtensionRuntimeClient: VpnExtensionRuntimeClient = new VpnExtensionRuntimeClient({
    shouldConnect: () => this.initialized,
    getSocketPath: (name: string) => AppManager.uiState.getSocketPath(name),
    onTopology: (snapshot: RuntimeAggregateState) => {
      Logger.debug(`VpnExtension runtime_topology received instances=${snapshot.instances?.length ?? 0}`, this)
      this.processRuntimeSnapshot(snapshot, true, false)
    },
    onPeerEvent: (peerEvent: RuntimePeerEventPayload) => {
      this.processRuntimePeerEvent(peerEvent, true)
    },
    onTrafficStats: (stats: TrafficStatsPayload) => {
      this.processTrafficStats(stats, true)
    },
    onLogs: (logData: VpnLogData) => {
      this.processLogs(logData.logs)
    },
    onRuntimeCommandResult: (result: VpnRuntimeCommandResultData) => {
      this.runtimeCommandResults.set(result.requestId, result)
      Logger.info(`VPN runtime command result command=${result.command} instance=${result.instanceId} success=${result.success} state=${result.state} error=${result.error ?? ''}`, this)
    },
    onRuntimeStatus: (status: VpnRuntimeStatusData) => {
      this.runtimeStatus = status
      Logger.info(`VPN runtime status instance=${status.instanceId} state=${status.state} generation=${status.generation}`,
        this)
    }
  })
  private optimisticRunningUntil: Map<string, number> = new Map()
  private runtimeStateCoordinator: RuntimeStateCoordinator = new RuntimeStateCoordinator({
    runningNetworks: this.runningNetworks,
    instanceInfos: this.instanceInfos,
    needTUN: this.needTUN,
    optimisticRunningUntil: this.optimisticRunningUntil,
    getInstanceName: (uuid: string) => this.getConfigName(uuid) ?? 'N/A',
    getFavoriteState: () => this.buildFavoriteCardState(),
    isVpnConnected: () => this.vpnExtensionRuntimeClient.isConnected(),
    isExtMode: () => true
  })
  private initialized: boolean = false
  private kernelRuntimeTopologyCallback: Callback<emitter.EventData> = (event: emitter.EventData) => {
    if (event?.data?.snapshot) {
      this.processRuntimeSnapshot(event.data.snapshot as RuntimeAggregateState, false, false)
    }
  }
  private kernelRuntimePeerEventCallback: Callback<emitter.EventData> = (event: emitter.EventData) => {
    if (event?.data?.peerEvent) {
      this.processRuntimePeerEvent(event.data.peerEvent as RuntimePeerEventPayload, false)
    }
  }
  private kernelTrafficStatsCallback: Callback<emitter.EventData> = (event: emitter.EventData) => {
    if (event?.data?.stats) {
      this.processTrafficStats(event.data.stats as TrafficStatsPayload, false)
    }
  }

  private enqueueOperation(action: () => Promise<void>): Promise<void> {
    const next = this.operationQueue.catch(() => {}).then(action)
    this.operationQueue = next
    return next
  }

  init() {
    if (this.initialized) {
      return
    }
    this.initialized = true
    EventHelper.emitterListener(KERNEL_RUNTIME_TOPOLOGY_EVENT, this.kernelRuntimeTopologyCallback)
    EventHelper.emitterListener(KERNEL_RUNTIME_PEER_EVENT, this.kernelRuntimePeerEventCallback)
    EventHelper.emitterListener(KERNEL_TRAFFIC_STATS_EVENT, this.kernelTrafficStatsCallback)

    this.logTimer = setInterval(() => {
      this.processLogs(easytier.drainLogLines())
    }, 500)

    this.connectToVpnExtension(VPN_EXTENSION_SOCKET_NAME)
  }

  destroy() {
    if (!this.initialized) {
      return
    }
    this.runtimeIntentGeneration++
    this.initialized = false
    EventHelper.emitterOff(KERNEL_RUNTIME_TOPOLOGY_EVENT, this.kernelRuntimeTopologyCallback)
    EventHelper.emitterOff(KERNEL_RUNTIME_PEER_EVENT, this.kernelRuntimePeerEventCallback)
    EventHelper.emitterOff(KERNEL_TRAFFIC_STATS_EVENT, this.kernelTrafficStatsCallback)
    if (this.logTimer !== undefined) {
      clearInterval(this.logTimer)
      this.logTimer = undefined
    }
    this.runtimeStateCoordinator.clearRunningState()
    this.runtimeStateCoordinator.reset()
    this.vpnExtensionRuntimeClient.close()
    this.pendingStartIds.clear()
    this.pendingStopIds.clear()
    this.acceptedRuntimeIds.clear()
    this.runtimeCommandResults.clear()
    this.runtimeStatus = undefined
  }

  version() {
    return easytier.easytierVersion()
  }

  convertToml2NetworkConfig(toml: string): string {
    return easytier.convertTomlToNetworkConfig(toml)
  }

  private buildFavoriteCardState(): FavoriteCardSignatureState {
    const favoriteUuid = AppManager.uiState.favorite ?? ''
    const favoriteName = favoriteUuid.length > 0 ? this.getConfigName(favoriteUuid) ?? favoriteUuid : ''
    return {
      favoriteUuid,
      favoriteName,
      favoriteRunning: this.isFavoritesRunning()
    }
  }

  public notifyFavoriteCardChanged(force: boolean = false): void {
    this.runtimeStateCoordinator.notifyFavoriteCardChanged(force)
  }

  private processRuntimePeerEvent(peerEvent: RuntimePeerEventPayload, fromVpn: boolean = true): void {
    this.runtimeStateCoordinator.processRuntimePeerEvent(peerEvent, fromVpn)
  }

  private processRuntimeSnapshot(snapshot: RuntimeAggregateState, fromVpn: boolean = true, includeTraffic: boolean = true): void {
    this.runtimeStateCoordinator.processRuntimeSnapshot(snapshot, fromVpn, includeTraffic)
  }

  private markOptimisticRunning(config: ConfigJson, displayName: string): void {
    this.runtimeStateCoordinator.markOptimisticRunning(config, displayName)
  }

  processLogs(logs: string[]) {
    logs.forEach((value) => {
      this.appLogs.add(value)
    })
  }

  processTrafficStats(stats: TrafficStatsPayload, fromVpn: boolean = true): void {
    this.runtimeStateCoordinator.processTrafficStats(stats, fromVpn)
  }

  private connectToVpnExtension(socketName: string): void {
    this.vpnExtensionRuntimeClient.connect(socketName)
  }

  public ensureRuntimeConnection(): void {
    if (!this.vpnExtensionRuntimeClient.isConnected()) {
      this.connectToVpnExtension(VPN_EXTENSION_SOCKET_NAME)
    }
  }

  public start(uuid: string | undefined = AppManager.uiState.selected, byCard: boolean = false): boolean {
    if (!uuid || this.pendingStartIds.has(uuid) || this.pendingStopIds.has(uuid) ||
      this.acceptedRuntimeIds.has(uuid) || this.isRunning(uuid)) {
      return false
    }
    const config: ConfigJson | undefined = this.getConfig(uuid)
    if (!config || !easytier.parseNetworkConfig(JSON.stringify(config))) {
      return false
    }
    this.pendingStartIds.add(uuid)
    void this.enqueueOperation(async () => {
      const started = await this.startInternal(uuid, byCard)
      if (started) {
        this.acceptedRuntimeIds.add(uuid)
      }
    }).catch((error: Error) => {
      Logger.error(`queued start failed instance=${uuid} error=${error.message}`, this)
    }).finally(() => {
      this.pendingStartIds.delete(uuid)
    })
    return true
  }

  private async startInternal(uuid: string, byCard: boolean): Promise<boolean> {
    const config: ConfigJson | undefined = this.getConfig(uuid)
    if (!config) {
      return false
    }
    Logger.debug(`start config requested instance=${uuid}`, this)
    if (!syncWholeConfig(uuid, this.getConfigName(uuid) ?? uuid, config)) {
      Logger.error(`start config sync failed instance=${uuid}`, this)
      return false
    }
    const startIntentGeneration = this.runtimeIntentGeneration
    const keepAliveStarted = await requestEntryKeepAliveStart(this.getConfigName(uuid) ?? uuid)
    if (!keepAliveStarted) {
      return false
    }
    const extensionReady = await orchestrateInstanceStart({
      config,
      configRootDir: AppManager.uiState.socketFilesDir,
      socketFilesDir: AppManager.uiState.socketFilesDir,
      addNeedTun: (instanceId: string) => {
        this.needTUN.add(instanceId)
      },
      connectToVpnExtension: (socketName: string) => {
        this.connectToVpnExtension(socketName)
      },
      isVpnExtensionConnected: () => {
        return this.vpnExtensionRuntimeClient.isConnected()
      },
      ensureContinuationSocket: () => {
        EventHelper.emitterPublish(ENTRY_SYNC_CONTINUATION_SOCKET_EVENT)
      },
      sendInvalidConfigToast: () => {
        sendToast("非法实例, 可能是序列化错误, 请上报日志.", $r("sys.symbol.exclamationmark_circle"), 1)
      }
    })
    if (!extensionReady) {
      await requestEntryKeepAliveStop()
      return false
    }
    const command = this.vpnExtensionRuntimeClient.enqueueCommand('start', uuid)
    const result = await this.waitForRuntimeCommandResult(command, startIntentGeneration)
    const started = result?.success === true && result.started !== false
    if (started) {
      if (!this.getRunningInstance(uuid)) {
        this.markOptimisticRunning(config, this.getConfigName(uuid) ?? uuid)
      }
      AppManager.runtimeStats.startLiveRefresh(true)
      this.notifyFavoriteCardChanged()
    } else {
      await this.rollbackVpnStart(command, uuid, result?.error ?? 'runtime start failed')
    }
    Logger.info(`start completed instance=${uuid} result=${started}`, this)
    return started
  }

  private isRuntimeIntentActive(intentGeneration: number): boolean {
    return this.initialized && this.runtimeIntentGeneration === intentGeneration
  }

  private async waitForRuntimeCommandResult(command: VpnRuntimeCommandData,
    intentGeneration: number): Promise<VpnRuntimeCommandResultData | undefined> {
    Logger.info(`waiting for VPN command=${command.command} request=${command.requestId}`, this)
    while (this.isRuntimeIntentActive(intentGeneration)) {
      const result = this.runtimeCommandResults.get(command.requestId)
      if (result !== undefined) {
        this.runtimeCommandResults.delete(command.requestId)
        return result
      }
      await new Promise<void>((resolve) => {
        setTimeout(resolve, 100)
      })
    }
    return undefined
  }

  private async rollbackVpnStart(command: VpnRuntimeCommandData, instanceId: string, reason: string): Promise<void> {
    this.vpnExtensionRuntimeClient.cancelCommand(command.requestId)
    this.runtimeCommandResults.delete(command.requestId)
    this.needTUN.delete(instanceId)
    this.acceptedRuntimeIds.delete(instanceId)
    this.runtimeStateCoordinator.clearRunningState()
    this.runtimeStateCoordinator.notifyRuntimeChanged()
    await requestEntryKeepAliveStop()
    Logger.error(`VPN extension start rolled back instance=${instanceId} reason=${reason}`, this)
  }

  public temp_start(name: string, config: ConfigJson): Promise<boolean> {
    const instanceId: string = (config.instance_id as string | undefined) ?? ''
    if (instanceId.length === 0 || this.pendingStartIds.has(instanceId) || this.pendingStopIds.has(instanceId) ||
      this.acceptedRuntimeIds.has(instanceId) || this.isRunning(instanceId)) {
      return Promise.resolve(false)
    }
    this.pendingStartIds.add(instanceId)
    let started = false
    return this.enqueueOperation(async () => {
      started = await this.startTemporaryInternal(name, config, instanceId)
      if (started) {
        this.acceptedRuntimeIds.add(instanceId)
      }
    }).then(() => started).catch((error: Error) => {
      Logger.error(`queued temporary start failed instance=${instanceId} error=${error.message}`, this)
      return false
    }).finally(() => {
      this.pendingStartIds.delete(instanceId)
    })
  }

  private async startTemporaryInternal(name: string, config: ConfigJson, instanceId: string): Promise<boolean> {
    await AppManager.permission.requestDistributePerm(false)
    config.hostname = getHostname()
    Logger.debug(`temporary start requested instance=${instanceId}`, this)
    if (!syncWholeConfig(instanceId, name, config)) {
      return false
    }
    this.temporaryConfigIds.add(instanceId)
    const startIntentGeneration = this.runtimeIntentGeneration
    const keepAliveStarted = await requestEntryKeepAliveStart(name)
    if (!keepAliveStarted) {
      AppManager.data.delConfig(instanceId)
      this.temporaryConfigIds.delete(instanceId)
      return false
    }
    const extensionReady = await orchestrateInstanceStart({
      config,
      configRootDir: AppManager.uiState.socketFilesDir,
      socketFilesDir: AppManager.uiState.socketFilesDir,
      addNeedTun: (startId: string) => {
        this.needTUN.add(startId)
      },
      connectToVpnExtension: (socketName: string) => {
        this.connectToVpnExtension(socketName)
      },
      isVpnExtensionConnected: () => {
        return this.vpnExtensionRuntimeClient.isConnected()
      },
      ensureContinuationSocket: () => {
        EventHelper.emitterPublish(ENTRY_SYNC_CONTINUATION_SOCKET_EVENT)
      },
      sendInvalidConfigToast: () => {
        sendToast("非法实例, 可能是序列化错误, 请上报日志.", $r("sys.symbol.exclamationmark_circle"), 1)
      }
    })
    if (!extensionReady) {
      await requestEntryKeepAliveStop()
      AppManager.data.delConfig(instanceId)
      this.temporaryConfigIds.delete(instanceId)
      return false
    }
    const command = this.vpnExtensionRuntimeClient.enqueueCommand('start', instanceId)
    const result = await this.waitForRuntimeCommandResult(command, startIntentGeneration)
    const started = result?.success === true && result.started !== false
    if (!started) {
      await this.rollbackVpnStart(command, instanceId, result?.error ?? 'temporary runtime start failed')
      AppManager.data.delConfig(instanceId)
      this.temporaryConfigIds.delete(instanceId)
      return false
    }
    if (!this.getRunningInstance(instanceId)) {
      this.markOptimisticRunning(config, name)
    }
    AppManager.runtimeStats.startLiveRefresh(true)
    this.notifyFavoriteCardChanged()
    Logger.info(`temporary start accepted instance=${instanceId}; waiting for runtime snapshot`, this)
    return true
  }

  public stop(): void {
    void this.stopAndWait().catch((error: Error) => {
      Logger.error(`stop failed: ${error.message}`, this)
    })
  }

  public stopAndWait(): Promise<void> {
    this.runtimeIntentGeneration++
    return this.enqueueOperation(() => this.stopInternal())
  }

  public startAfterStop(uuid: string | undefined = AppManager.uiState.selected, byCard: boolean = false): Promise<boolean> {
    if (!uuid || this.pendingStartIds.has(uuid) || this.pendingStopIds.has(uuid)) {
      return Promise.resolve(false)
    }
    this.runtimeIntentGeneration++
    this.pendingStartIds.add(uuid)
    let started = false
    return this.enqueueOperation(async () => {
      if (this.runningNetworks.size > 0 || this.acceptedRuntimeIds.size > 0) {
        await this.stopInternal()
      }
      started = await this.startInternal(uuid, byCard)
      if (started) {
        this.acceptedRuntimeIds.add(uuid)
      }
    }).then(() => started).catch((error: Error) => {
      Logger.error(`startAfterStop failed instance=${uuid} error=${error.message}`, this)
      return false
    }).finally(() => {
      this.pendingStartIds.delete(uuid)
    })
  }

  private ensureVpnExtensionReady(): Promise<boolean> {
    return VpnExtensionAbilityController.start({
      configRootDir: AppManager.uiState.socketFilesDir,
      socketFilesDir: AppManager.uiState.socketFilesDir,
      ensureContinuationSocket: () => {
        EventHelper.emitterPublish(ENTRY_SYNC_CONTINUATION_SOCKET_EVENT)
      },
      connectToVpnExtension: (socketName: string) => {
        this.connectToVpnExtension(socketName)
      },
      isConnected: () => {
        return this.vpnExtensionRuntimeClient.isConnected()
      }
    })
  }

  private async stopInternal(): Promise<void> {
    const temporaryRunningIds = Array.from(this.temporaryConfigIds.values())
    AppManager.runtimeStats.stopLiveRefresh()
    const runtimeIds = this.getRuntimeIntentIds()
    const instanceId = runtimeIds[0] ?? this.runtimeStatus?.instanceId ?? ''
    if (instanceId.length > 0) {
      const extensionReady = await this.ensureVpnExtensionReady()
      if (!extensionReady) {
        throw new Error('VPN extension is unavailable for runtime stop')
      }
      const intentGeneration = this.runtimeIntentGeneration
      const command = this.vpnExtensionRuntimeClient.enqueueCommand('stop', instanceId)
      const result = await this.waitForRuntimeCommandResult(command, intentGeneration)
      if (!result?.success) {
        throw new Error(`VPN runtime stop failed: ${result?.error ?? 'command cancelled'}`)
      }
    }
    await requestEntryKeepAliveStop()

    // 底层 stop/destroy 全部结束后才清 UI，下一次 start 不会插入旧销毁事务。
    this.runtimeStateCoordinator.clearRunningState()
    this.acceptedRuntimeIds.clear()
    this.runtimeCommandResults.clear()
    this.runtimeStateCoordinator.notifyRuntimeChanged()

    this.notifyFavoriteCardChanged(true)
    temporaryRunningIds.forEach((configId) => {
      AppManager.data.delConfig(configId)
      this.temporaryConfigIds.delete(configId)
    })
    let stack = HMRouterMgr.getPathStack("MainNavigation")!.getAllPathName()
    if (stack[stack.length-1] == "StatusPage") {
      HMRouterMgr.pop()
    }
  }

  public stopConfig(uuid: string | undefined): boolean {
    const running = this.getRunningInstance(uuid)
    if (!uuid || this.pendingStopIds.has(uuid) || (!running && !this.acceptedRuntimeIds.has(uuid))) {
      return false
    }
    this.runtimeIntentGeneration++
    const stopId = running?.configId || running?.instanceId || uuid
    this.pendingStopIds.add(uuid)
    this.pendingStopIds.add(stopId)
    void this.enqueueOperation(async () => {
      await this.stopConfigInternal(uuid, stopId, running)
    }).catch((error: Error) => {
      Logger.error(`queued stop failed instance=${stopId} error=${error.message}`, this)
    }).finally(() => {
      this.pendingStopIds.delete(uuid)
      this.pendingStopIds.delete(stopId)
    })
    return true
  }

  private async stopConfigInternal(_uuid: string, _stopId: string,
    _running: RuntimeInstanceState | undefined): Promise<void> {
    await this.stopInternal()
  }

  public isRunning(uuid?: string): boolean {
    return this.getRunningInstance(uuid) !== undefined
  }

  public hasActiveOrStartingRuntime(): boolean {
    return this.runningNetworks.size > 0 || this.acceptedRuntimeIds.size > 0 ||
      this.pendingStartIds.size > 0 || this.pendingStopIds.size > 0
  }

  public getRunningInstance(uuid?: string): RuntimeInstanceState | undefined {
    return findRunningInstance(this.runningNetworks, uuid)
  }

  public getConfirmedRunningInstance(uuid?: string): RuntimeInstanceState | undefined {
    const running = this.getRunningInstance(uuid)
    if (!running) {
      return undefined
    }
    const aliases: Array<string | undefined> = [uuid, running.configId, running.instanceId]
    for (const alias of aliases) {
      if (alias && this.optimisticRunningUntil.has(alias)) {
        return undefined
      }
    }
    return running
  }

  public isRuntimeStarting(uuid: string): boolean {
    if (this.pendingStartIds.has(uuid) || this.acceptedRuntimeIds.has(uuid)) {
      return this.getConfirmedRunningInstance(uuid) === undefined
    }
    return this.getRunningInstance(uuid) !== undefined && this.getConfirmedRunningInstance(uuid) === undefined
  }

  public getRunningInstances(): RuntimeInstanceState[] {
    return listRunningInstances(this.runningNetworks)
  }

  public getRuntimeIntentIds(): string[] {
    const ids: string[] = []
    this.acceptedRuntimeIds.forEach((id: string) => {
      if (id.length > 0 && ids.indexOf(id) < 0) {
        ids.push(id)
      }
    })
    this.getRunningInstances().forEach((instance: RuntimeInstanceState) => {
      const aliases: string[] = [instance.configId, instance.instanceId]
      aliases.forEach((id: string) => {
        if (id.length > 0 && ids.indexOf(id) < 0) {
          ids.push(id)
        }
      })
    })
    return ids
  }

  public restartForNetworkChange(ids: string[]): Promise<NetworkRestartResult> {
    const intentGeneration = this.runtimeIntentGeneration
    let result: NetworkRestartResult = {
      stopped: false,
      started: false,
      cancelled: true
    }
    return this.enqueueOperation(async () => {
      const activeIds = this.getRuntimeIntentIds()
      const restartIds: string[] = []
      ids.forEach((id: string) => {
        if (activeIds.indexOf(id) >= 0 && restartIds.indexOf(id) < 0) {
          restartIds.push(id)
        }
      })
      if (intentGeneration !== this.runtimeIntentGeneration || restartIds.length === 0) {
        return
      }
      const extensionReady = await this.ensureVpnExtensionReady()
      if (!extensionReady || intentGeneration !== this.runtimeIntentGeneration) {
        return
      }
      const command = this.vpnExtensionRuntimeClient.enqueueCommand('restart', restartIds[0])
      const commandResult = await this.waitForRuntimeCommandResult(command, intentGeneration)
      if (!commandResult) {
        return
      }
      result = {
        stopped: commandResult.stopped ?? commandResult.success,
        started: commandResult.started ?? commandResult.success,
        cancelled: !commandResult.success && commandResult.error === 'runtime_restart_cancelled'
      }
      if (result.stopped && !result.started) {
        AppManager.runtimeStats.stopLiveRefresh()
        this.runtimeStateCoordinator.clearRunningState()
        this.acceptedRuntimeIds.clear()
        this.runtimeStateCoordinator.notifyRuntimeChanged()
        this.notifyFavoriteCardChanged(true)
        await requestEntryKeepAliveStop()
      }
    }).then(() => result)
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

  public listLogFiles(): LogFileEntry[] {
    return LogCenterService.listLogFiles()
  }

  public readLogFileLines(fileName: string): string[] {
    return LogCenterService.readLogFileLines(fileName)
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
    LogCenterService.writeAndShareLogs(this.appLogs.join2String())
  }

  public writeAndShareLogFile(fileName: string) {
    LogCenterService.writeAndShareLogFile(fileName)
  }

  public writeAndShareCrashLog() {
    LogCenterService.writeAndShareCrashLog()
  }
}
