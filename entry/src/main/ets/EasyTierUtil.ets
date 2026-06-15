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
import { RuntimePeerEventPayload, TrafficStatsPayload, VpnLogData } from './infrastructure/bridge/kernel/KernelBridgeTypes'
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
import { shouldUseSubprocessRuntimeMode, VPN_EXTENSION_SOCKET_NAME } from './services/runtime/AbilityRuntimePolicy'
import {
  ENTRY_SYNC_CONTINUATION_SOCKET_EVENT,
  KERNEL_RUNTIME_PEER_EVENT,
  KERNEL_RUNTIME_TOPOLOGY_EVENT,
  KERNEL_TRAFFIC_STATS_EVENT,
  START_BACKGROUND_EVENT,
  STOP_BACKGROUND_EVENT
} from './types/events/RuntimeEventTypes'

@Concurrent
async function stopKernelWorker(instanceIds: string[]): Promise<void> {
  instanceIds.forEach((instanceId) => {
    if (instanceId.length > 0) {
      easytier.stopKernel(instanceId)
    }
  })
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

  private shouldUseExtMode(): boolean {
    return AppManager.uiState.ext_mode && shouldUseSubprocessRuntimeMode()
  }

  private stopKernelAsync(instanceIds: string[], reason: string): void {
    const uniqueIds: string[] = []
    instanceIds.forEach((instanceId) => {
      if (instanceId.length > 0 && uniqueIds.indexOf(instanceId) < 0) {
        uniqueIds.push(instanceId)
      }
    })
    if (uniqueIds.length === 0) {
      return
    }
    taskpool.execute(stopKernelWorker, uniqueIds).catch((error: Error) => {
      Logger.error(`stopKernelAsync failed reason=${reason}, ids=${JSON.stringify(uniqueIds)}, error=${error.message}`, this)
    })
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

  private connectToVpnExtension(socketName: string) {
    this.vpnExtensionRuntimeClient.connect(socketName)
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
          extMode: this.shouldUseExtMode(),
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
            EventHelper.emitterPublish(ENTRY_SYNC_CONTINUATION_SOCKET_EVENT)
          },
          requestVpnPerm: (callback: () => void) => {
            AppManager.permission.requestVpnPerm(callback)
          },
          publishStartBg: (cfg: string, startId: string | undefined, startName: string) => {
            EventHelper.emitterPublish(START_BACKGROUND_EVENT, {
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
          AppManager.runtimeStats.startLiveRefresh(true)
          this.notifyFavoriteCardChanged()
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
        extMode: this.shouldUseExtMode(),
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
          EventHelper.emitterPublish(ENTRY_SYNC_CONTINUATION_SOCKET_EVENT)
        },
        requestVpnPerm: (callback: () => void) => {
          AppManager.permission.requestVpnPerm(callback)
        },
        publishStartBg: (cfg: string, uuid: string | undefined, startName: string) => {
          EventHelper.emitterPublish(START_BACKGROUND_EVENT, {
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
        AppManager.runtimeStats.startLiveRefresh(true)
        this.notifyFavoriteCardChanged()
      }
      return started
    } else {
      return Promise.resolve(false)
    }
  }

  public stop() {
    const temporaryRunningIds = Array.from(this.temporaryConfigIds.values())
    AppManager.runtimeStats.stopLiveRefresh()
    if (this.shouldUseExtMode()) {
      VpnExtensionAbilityController.stop()
      this.vpnExtensionRuntimeClient.close()
    } else {
      const runningIds = Array.from(this.runningNetworks.keys()).filter((value) => {
        return value.length > 0
      }) as string[]
      EventHelper.emitterPublish(STOP_BACKGROUND_EVENT)
      this.stopKernelAsync(runningIds, 'stop_all')
    }

    // 显式清理 UI 状态
    this.runtimeStateCoordinator.clearRunningState()
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
    if (!uuid || !running) {
      return false
    }
    if (this.shouldUseExtMode()) {
      this.stop()
      return true
    }
    const stopId = running.configId || running.instanceId || uuid
    this.runtimeStateCoordinator.removeRunningInstanceAliases(running, uuid)
    if (this.temporaryConfigIds.has(uuid)) {
      AppManager.data.delConfig(uuid)
      this.temporaryConfigIds.delete(uuid)
    }
    if (this.runningNetworks.size === 0) {
      AppManager.runtimeStats.stopLiveRefresh()
      EventHelper.emitterPublish(STOP_BACKGROUND_EVENT)
    }
    this.notifyFavoriteCardChanged(true)
    let stack = HMRouterMgr.getPathStack("MainNavigation")!.getAllPathName()
    if (stack[stack.length-1] == "StatusPage") {
      HMRouterMgr.pop()
    }
    this.runtimeStateCoordinator.notifyRuntimeChanged()
    this.stopKernelAsync([stopId], 'stop_config')
    return true
  }

  public isRunning(uuid?: string): boolean {
    return this.getRunningInstance(uuid) !== undefined
  }

  public getRunningInstance(uuid?: string): RuntimeInstanceState | undefined {
    return findRunningInstance(this.runningNetworks, uuid)
  }

  public getRunningInstances(): RuntimeInstanceState[] {
    return listRunningInstances(this.runningNetworks)
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
