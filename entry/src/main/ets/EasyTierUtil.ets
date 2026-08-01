import easytier from 'easytier-ohrs'
import { EventHelper } from './util/EventHelper'
import { AppManager } from './AppManager'
import { Logger, LogLocate } from './shared/logging/Logger'
import { sendToast } from './ToastUtil'
import { InstanceInfo } from './class/InstanceInfo'
import { emitter } from '@kit.BasicServicesKit'
import { getDefaultConfig } from './config/defaults/ConfigDefaults'
import { JSON, taskpool } from '@kit.ArkTS'
import { LogDataSource } from './class/data_source/LogDataSource'
import { HMRouterMgr } from '@hadss/hmrouter'
import { syncWholeConfig } from './ConfigSyncUtil'
import { ConfigJson } from './config/schema/SchemaConfig'
import { RuntimeAggregateState, RuntimeInstanceState } from './types/runtime/RuntimeTypes'
import {
  RuntimePeerEventPayload,
  TrafficStatsPayload,
  VpnLogData,
  VpnRuntimeStartRequestData,
  VpnRuntimeStartResultData
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
import { requestEntryRuntimeStart, requestEntryRuntimeStop } from './services/runtime/EntryRuntimeStopBridge'
import { shouldUseSubprocessRuntimeMode, VPN_EXTENSION_SOCKET_NAME } from './services/runtime/AbilityRuntimePolicy'
import {
  NetworkRestartResult,
  softRestartStoredInstances
} from './services/runtime/NetworkChangeWatchdog'
import {
  ENTRY_SYNC_CONTINUATION_SOCKET_EVENT,
  KERNEL_RUNTIME_PEER_EVENT,
  KERNEL_RUNTIME_TOPOLOGY_EVENT,
  KERNEL_TRAFFIC_STATS_EVENT
} from './types/events/RuntimeEventTypes'

@Concurrent
async function stopKernelWorker(instanceIds: string[]): Promise<boolean> {
  let stopped = true
  instanceIds.forEach((instanceId) => {
    if (instanceId.length > 0) {
      if (!easytier.stopKernel(instanceId)) {
        stopped = false
      }
    }
  })
  return stopped
}

enum RuntimeExecutionMode {
  ENTRY = 0,
  VPN_EXTENSION = 1
}

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
  private vpnStartResults: Map<string, boolean> = new Map()
  private activeRuntimeMode: RuntimeExecutionMode | undefined = undefined
  private vpnExtensionRuntimeClient: VpnExtensionRuntimeClient = new VpnExtensionRuntimeClient({
    isExtMode: () => this.shouldUseExtMode(),
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
    onRuntimeStartResult: (result: VpnRuntimeStartResultData) => {
      if (result.instanceId.length === 0) {
        return
      }
      this.vpnStartResults.set(result.instanceId, result.started)
      this.vpnExtensionRuntimeClient.clearRuntimeStartRequest(result.instanceId)
      Logger.info(`VPN extension kernel start result instance=${result.instanceId} started=${result.started} error=${result.error ?? ''}`, this)
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
    isExtMode: () => this.shouldUseExtMode()
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

  private preferredRuntimeMode(): RuntimeExecutionMode {
    return AppManager.uiState.ext_mode && shouldUseSubprocessRuntimeMode() ?
      RuntimeExecutionMode.VPN_EXTENSION : RuntimeExecutionMode.ENTRY
  }

  private shouldUseExtMode(): boolean {
    const mode = this.activeRuntimeMode ?? this.preferredRuntimeMode()
    return mode === RuntimeExecutionMode.VPN_EXTENSION
  }

  private stopKernelAsync(instanceIds: string[], reason: string): Promise<boolean> {
    const uniqueIds: string[] = []
    instanceIds.forEach((instanceId) => {
      if (instanceId.length > 0 && uniqueIds.indexOf(instanceId) < 0) {
        uniqueIds.push(instanceId)
      }
    })
    if (uniqueIds.length === 0) {
      return Promise.resolve(true)
    }
    return taskpool.execute(stopKernelWorker, uniqueIds).then((result: Object) => {
      return result as boolean
    }).catch((error: Error) => {
      Logger.error(`stopKernelAsync failed reason=${reason}, ids=${JSON.stringify(uniqueIds)}, error=${error.message}`, this)
      return false
    })
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

    if (this.shouldUseExtMode()) {
      this.connectToVpnExtension(VPN_EXTENSION_SOCKET_NAME)
    }
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
    this.vpnStartResults.clear()
    this.activeRuntimeMode = undefined
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

  private connectToVpnExtension(socketName: string, startRequest?: VpnRuntimeStartRequestData) {
    this.vpnExtensionRuntimeClient.connect(socketName, startRequest)
  }

  public ensureRuntimeConnection(): void {
    if (this.shouldUseExtMode() && !this.vpnExtensionRuntimeClient.isConnected()) {
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
    const runtimeMode = this.activeRuntimeMode ?? this.preferredRuntimeMode()
    const extMode = runtimeMode === RuntimeExecutionMode.VPN_EXTENSION
    const startIntentGeneration = this.runtimeIntentGeneration
    this.activeRuntimeMode = runtimeMode
    if (extMode) {
      this.vpnStartResults.delete(uuid)
    }
    let started = await orchestrateInstanceStart({
      config,
      name: this.getConfigName(uuid) ?? uuid,
      extMode,
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
      connectToVpnExtension: (socketName: string, request: VpnRuntimeStartRequestData) => {
        this.connectToVpnExtension(socketName, request)
      },
      ensureContinuationSocket: () => {
        EventHelper.emitterPublish(ENTRY_SYNC_CONTINUATION_SOCKET_EVENT)
      },
      startEntryRuntime: (cfg: string, startId: string | undefined, startName: string,
        shouldProtect: boolean): Promise<boolean> => {
        return requestEntryRuntimeStart(cfg, byCard ? undefined : startId, startName, shouldProtect)
      },
      sendInvalidConfigToast: () => {
        sendToast("非法实例, 可能是序列化错误, 请上报日志.", $r("sys.symbol.exclamationmark_circle"), 1)
      }
    })
    if (started && extMode) {
      started = await this.waitForRuntimeConfirmation(uuid, startIntentGeneration)
      this.vpnStartResults.delete(uuid)
      if (!started) {
        if (this.isVpnStartIntentActive(startIntentGeneration)) {
          Logger.error(`VPN extension reported a runtime start failure instance=${uuid}`, this)
          await this.rollbackVpnStart(uuid, 'runtime start failed')
        } else {
          Logger.info(`VPN extension start wait cancelled instance=${uuid}`, this)
        }
      }
    }
    if (!started && extMode && this.isVpnStartIntentActive(startIntentGeneration)) {
      await this.rollbackVpnStart(uuid, 'extension start rejected')
    }
    if (started) {
      if (!this.getRunningInstance(uuid)) {
        this.markOptimisticRunning(config, this.getConfigName(uuid) ?? uuid)
      }
      AppManager.runtimeStats.startLiveRefresh(true)
      this.notifyFavoriteCardChanged()
    } else if (!extMode && this.acceptedRuntimeIds.size === 0 && this.runningNetworks.size === 0) {
      this.activeRuntimeMode = undefined
    }
    Logger.info(`start completed instance=${uuid} result=${started}`, this)
    return started
  }

  private isVpnStartIntentActive(intentGeneration: number): boolean {
    return this.initialized && this.activeRuntimeMode === RuntimeExecutionMode.VPN_EXTENSION &&
      this.runtimeIntentGeneration === intentGeneration
  }

  private async waitForRuntimeConfirmation(uuid: string, intentGeneration: number): Promise<boolean> {
    Logger.info(`waiting for VPN authorization and runtime confirmation instance=${uuid}`, this)
    while (this.isVpnStartIntentActive(intentGeneration)) {
      const startResult = this.vpnStartResults.get(uuid)
      if (startResult !== undefined) {
        return startResult
      }
      if (this.getRunningInstance(uuid)) {
        return true
      }
      await new Promise<void>((resolve) => {
        setTimeout(resolve, 100)
      })
    }
    return false
  }

  private async rollbackVpnStart(instanceId: string, reason: string): Promise<void> {
    this.vpnStartResults.delete(instanceId)
    this.needTUN.delete(instanceId)
    this.acceptedRuntimeIds.delete(instanceId)
    this.runtimeStateCoordinator.clearRunningState()
    this.runtimeStateCoordinator.notifyRuntimeChanged()
    this.vpnExtensionRuntimeClient.close()
    try {
      await VpnExtensionAbilityController.stop()
    } catch (error) {
      const err = error as Error
      Logger.error(`rollback VPN extension failed reason=${reason} error=${err.message}`, this)
    } finally {
      this.activeRuntimeMode = undefined
    }
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
    const runtimeMode = this.activeRuntimeMode ?? this.preferredRuntimeMode()
    const extMode = runtimeMode === RuntimeExecutionMode.VPN_EXTENSION
    const startIntentGeneration = this.runtimeIntentGeneration
    this.activeRuntimeMode = runtimeMode
    if (extMode) {
      this.vpnStartResults.delete(instanceId)
    }
    let started = await orchestrateInstanceStart({
      config,
      name,
      extMode,
      socketFilesDir: AppManager.uiState.socketFilesDir,
      vpnRoutes: AppManager.uiState.vpn_routes,
      whiteList: AppManager.uiState.white_list,
      blackList: AppManager.preference.getBlackList(),
      dns: AppManager.uiState.dns,
      dev: AppManager.uiState.dev,
      forceGlobal: AppManager.uiState.force_global,
      coreLog: AppManager.uiState.core_log,
      debugLog: AppManager.uiState.debug_log,
      addNeedTun: (startId: string) => {
        this.needTUN.add(startId)
      },
      connectToVpnExtension: (socketName: string, request: VpnRuntimeStartRequestData) => {
        this.connectToVpnExtension(socketName, request)
      },
      ensureContinuationSocket: () => {
        EventHelper.emitterPublish(ENTRY_SYNC_CONTINUATION_SOCKET_EVENT)
      },
      startEntryRuntime: (cfg: string, uuid: string | undefined, startName: string,
        shouldProtect: boolean): Promise<boolean> => {
        return requestEntryRuntimeStart(cfg, uuid, startName, shouldProtect)
      },
      sendInvalidConfigToast: () => {
        sendToast("非法实例, 可能是序列化错误, 请上报日志.", $r("sys.symbol.exclamationmark_circle"), 1)
      }
    })
    if (started && extMode) {
      started = await this.waitForRuntimeConfirmation(instanceId, startIntentGeneration)
      this.vpnStartResults.delete(instanceId)
      if (!started) {
        if (this.isVpnStartIntentActive(startIntentGeneration)) {
          await this.rollbackVpnStart(instanceId, 'temporary runtime start failed')
        } else {
          Logger.info(`temporary VPN extension start wait cancelled instance=${instanceId}`, this)
        }
      }
    }
    if (!started && extMode && this.isVpnStartIntentActive(startIntentGeneration)) {
      await this.rollbackVpnStart(instanceId, 'temporary extension start rejected')
    }
    if (!started) {
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

  private async stopInternal(): Promise<void> {
    const temporaryRunningIds = Array.from(this.temporaryConfigIds.values())
    AppManager.runtimeStats.stopLiveRefresh()
    const runtimeMode = this.activeRuntimeMode ?? this.preferredRuntimeMode()
    let stopError: Error | undefined = undefined
    if (runtimeMode === RuntimeExecutionMode.VPN_EXTENSION) {
      try {
        await VpnExtensionAbilityController.stop(() => {
          return this.vpnExtensionRuntimeClient.waitForDisconnected()
        })
      } catch (error) {
        stopError = error as Error
        Logger.error(`VPN extension stop failed: ${stopError.message}`, this)
      }
      if (!stopError) {
        this.vpnExtensionRuntimeClient.close()
      }
    } else {
      const runningIds = Array.from(this.runningNetworks.keys()).concat(Array.from(this.acceptedRuntimeIds.values())).filter((value) => {
        return value.length > 0
      }).filter((value, index, values) => values.indexOf(value) === index) as string[]
      const kernelStopped = await this.stopKernelAsync(runningIds, 'stop_all')
      try {
        await requestEntryRuntimeStop()
      } catch (error) {
        stopError = error as Error
        Logger.error(`entry runtime stop failed: ${stopError.message}`, this)
      }
      if (!kernelStopped && !stopError) {
        stopError = new Error('kernel rejected one or more stop requests')
      }
    }

    // 底层 stop/destroy 全部结束后才清 UI，下一次 start 不会插入旧销毁事务。
    this.runtimeStateCoordinator.clearRunningState()
    this.acceptedRuntimeIds.clear()
    this.vpnStartResults.clear()
    this.activeRuntimeMode = undefined
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
    if (stopError) {
      throw new Error(`runtime stop incomplete: ${stopError.message}`)
    }
  }

  public stopConfig(uuid: string | undefined): boolean {
    const running = this.getRunningInstance(uuid)
    if (!uuid || this.pendingStopIds.has(uuid) || (!running && !this.acceptedRuntimeIds.has(uuid))) {
      return false
    }
    this.runtimeIntentGeneration++
    const stopId = running?.configId || running?.instanceId || uuid
    const runtimeMode = this.activeRuntimeMode ?? this.preferredRuntimeMode()
    this.pendingStopIds.add(uuid)
    this.pendingStopIds.add(stopId)
    void this.enqueueOperation(async () => {
      await this.stopConfigInternal(uuid, stopId, running, runtimeMode)
    }).catch((error: Error) => {
      Logger.error(`queued stop failed instance=${stopId} error=${error.message}`, this)
    }).finally(() => {
      this.pendingStopIds.delete(uuid)
      this.pendingStopIds.delete(stopId)
    })
    return true
  }

  private async stopConfigInternal(uuid: string, stopId: string, running: RuntimeInstanceState | undefined,
    runtimeMode: RuntimeExecutionMode): Promise<void> {
    if (runtimeMode === RuntimeExecutionMode.VPN_EXTENSION) {
      await this.stopInternal()
      return
    }
    const aliases: string[] = [uuid, stopId]
    if (running) {
      if (running.configId.length > 0 && aliases.indexOf(running.configId) < 0) {
        aliases.push(running.configId)
      }
      if (running.instanceId.length > 0 && aliases.indexOf(running.instanceId) < 0) {
        aliases.push(running.instanceId)
      }
    }
    const remainingRunning = this.getRunningInstances().filter((instance: RuntimeInstanceState) => {
      return aliases.indexOf(instance.configId) < 0 && aliases.indexOf(instance.instanceId) < 0
    })
    const remainingAccepted: string[] = []
    this.acceptedRuntimeIds.forEach((id: string) => {
      if (aliases.indexOf(id) < 0) {
        remainingAccepted.push(id)
      }
    })
    const stoppingLastRuntime = remainingRunning.length === 0 && remainingAccepted.length === 0
    const kernelStopped = await this.stopKernelAsync([stopId], 'stop_config')
    if (!kernelStopped) {
      throw new Error(`kernel rejected stop request instance=${stopId}`)
    }
    let runtimeStopError: Error | undefined = undefined
    if (stoppingLastRuntime) {
      try {
        await requestEntryRuntimeStop()
      } catch (error) {
        runtimeStopError = error as Error
        Logger.error(`last Entry runtime cleanup failed: ${runtimeStopError.message}`, this)
      }
    }
    aliases.forEach((id: string) => {
      this.acceptedRuntimeIds.delete(id)
    })
    if (running) {
      this.runtimeStateCoordinator.removeRunningInstanceAliases(running, uuid)
    }
    aliases.forEach((id: string) => {
      if (this.temporaryConfigIds.has(id)) {
        AppManager.data.delConfig(id)
        this.temporaryConfigIds.delete(id)
      }
    })
    if (stoppingLastRuntime) {
      AppManager.runtimeStats.stopLiveRefresh()
      this.activeRuntimeMode = undefined
    }
    this.notifyFavoriteCardChanged(true)
    const stack = HMRouterMgr.getPathStack("MainNavigation")!.getAllPathName()
    if (stack[stack.length-1] == "StatusPage") {
      HMRouterMgr.pop()
    }
    this.runtimeStateCoordinator.notifyRuntimeChanged()
    if (runtimeStopError) {
      throw runtimeStopError
    }
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

  public restartForNetworkChange(ids: string[], beginVpnRestart: () => Promise<boolean>,
    completeVpnRestart: (started: boolean) => Promise<void>): Promise<NetworkRestartResult> {
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
      const vpnReady = await beginVpnRestart()
      if (!vpnReady || intentGeneration !== this.runtimeIntentGeneration) {
        if (vpnReady) {
          await completeVpnRestart(false)
        }
        return
      }
      try {
        result = await softRestartStoredInstances(restartIds, () => {
          return intentGeneration === this.runtimeIntentGeneration
        })
      } finally {
        const runtimeStillWanted = intentGeneration === this.runtimeIntentGeneration
        await completeVpnRestart(result.started && runtimeStillWanted)
        if (!runtimeStillWanted && result.started) {
          await this.stopKernelAsync(restartIds, 'cancelled_network_restart')
          result = {
            stopped: result.stopped,
            started: false,
            cancelled: true
          }
        }
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
