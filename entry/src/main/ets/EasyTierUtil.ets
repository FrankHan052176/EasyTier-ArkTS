import easytier from 'easytier-ohrs'
import { EventHelper } from './util/EventHelper'
import { AppManager } from './AppManager'
import { Logger, LogLocate } from './shared/logging/Logger'
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
  TrafficStatsPayload
} from './infrastructure/bridge/kernel/KernelBridgeTypes'
import { getEditingConfig as getEditingStoredConfig, getStoredConfig, getStoredConfigLabel, getStoredConfigName, listStoredConfigs as listStoredConfigEntries, StoredConfigMetaLite } from './services/config/storage/StoredConfigService'
import { getHostname } from './util/Conversion'
import { LogFileEntry } from './types/logging/LogFileTypes'
import { LogCenterService } from './services/logging/LogCenterService'
import { findRunningInstance, listRunningInstances } from './services/runtime/RuntimeStateReducer'
import { FavoriteCardSignatureState } from './services/runtime/RuntimeNotificationService'
import { RuntimeStateCoordinator } from './services/runtime/RuntimeStateCoordinator'
import { RUNTIME_STATS_STALE_AFTER_MS } from './services/runtime/RuntimeStatsService'
import {
  EntryRuntimeStartRequest,
  requestEntryRuntimeStart,
  requestEntryRuntimeStop
} from './services/runtime/EntryRuntimeStopBridge'
import { requestEntryKeepAliveStart, requestEntryKeepAliveStop } from './services/runtime/EntryKeepAliveBridge'
import {
  NetworkRestartResult,
  softRestartOneShotInstance,
  softRestartStoredInstances
} from './services/runtime/NetworkChangeWatchdog'
import {
  KERNEL_RUNTIME_PEER_EVENT,
  KERNEL_RUNTIME_TOPOLOGY_EVENT,
  KERNEL_TRAFFIC_STATS_EVENT
} from './types/events/RuntimeEventTypes'

const KERNEL_HEARTBEAT_STALE_AFTER_MS = 5000

export interface RuntimeHealthTransportSnapshot {
  connected: boolean
  connectedAt: number
  disconnectedAt: number
  lastMessageAt: number
  lastTrafficStatsAt: number
}

export interface RuntimeHealthSummary {
  state: string
  text: string
  warning: boolean
  checkedAt: number
  bridge: RuntimeHealthTransportSnapshot
  runtimeStatsUpdatedAt: number
}

const FOREGROUND_LOG_DRAIN_INTERVAL_MS = 500
const BACKGROUND_LOG_DRAIN_INTERVAL_MS = 5000
const BACKGROUND_RUNTIME_REFRESH_INTERVAL_MS = 5000

@LogLocate("EasyTierUtil")
@ObservedV2
export class EasyTierUtil {
  @Trace appLogs: LogDataSource = new LogDataSource
  @Trace runningNetworks: Map<string, RuntimeInstanceState> = new Map()
  @Trace instanceInfos: Map<string, InstanceInfo> = new Map()
  @Trace needTUN: Set<string> = new Set()
  @Trace temporaryConfigIds: Set<string> = new Set()
  private logTimer: number | undefined
  private uiForeground: boolean = true
  private lastBackgroundTopologyAt: number = 0
  private lastBackgroundTrafficAt: number = 0
  private operationQueue: Promise<void> = Promise.resolve()
  private runtimeIntentGeneration: number = 0
  private pendingStartIds: Set<string> = new Set()
  private pendingStopIds: Set<string> = new Set()
  private acceptedRuntimeIds: Set<string> = new Set()
  private activeOneShotConfigJson: string = ''
  private activeOneShotRequestId: string = ''
  private initializedAt: number = 0
  private lastTrafficStatsAt: number = 0
  private optimisticRunningUntil: Map<string, number> = new Map()
  private runtimeStateCoordinator: RuntimeStateCoordinator = new RuntimeStateCoordinator({
    runningNetworks: this.runningNetworks,
    instanceInfos: this.instanceInfos,
    needTUN: this.needTUN,
    optimisticRunningUntil: this.optimisticRunningUntil,
    getInstanceName: (uuid: string) => this.getConfigName(uuid) ?? 'N/A',
    getFavoriteState: () => this.buildFavoriteCardState(),
    isVpnConnected: () => false,
    isExtMode: () => false
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
    this.initializedAt = Date.now()
    EventHelper.emitterListener(KERNEL_RUNTIME_TOPOLOGY_EVENT, this.kernelRuntimeTopologyCallback)
    EventHelper.emitterListener(KERNEL_RUNTIME_PEER_EVENT, this.kernelRuntimePeerEventCallback)
    EventHelper.emitterListener(KERNEL_TRAFFIC_STATS_EVENT, this.kernelTrafficStatsCallback)

    this.restartLogDrainTimer()

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
    this.stopLogDrainTimer()
    this.runtimeStateCoordinator.clearRunningState()
    this.runtimeStateCoordinator.reset()
    this.pendingStartIds.clear()
    this.pendingStopIds.clear()
    this.acceptedRuntimeIds.clear()
    this.activeOneShotConfigJson = ''
    this.activeOneShotRequestId = ''
    this.initializedAt = 0
    this.lastTrafficStatsAt = 0
    this.lastBackgroundTopologyAt = 0
    this.lastBackgroundTrafficAt = 0
  }

  setUiForeground(foreground: boolean): void {
    if (this.uiForeground === foreground) {
      return
    }
    this.uiForeground = foreground
    if (foreground) {
      this.lastBackgroundTopologyAt = 0
      this.lastBackgroundTrafficAt = 0
    }
    if (!this.initialized) {
      return
    }
    this.restartLogDrainTimer()
    if (foreground) {
      this.processLogs(easytier.drainLogLines())
    }
  }

  private restartLogDrainTimer(): void {
    this.stopLogDrainTimer()
    const intervalMs = this.uiForeground ? FOREGROUND_LOG_DRAIN_INTERVAL_MS : BACKGROUND_LOG_DRAIN_INTERVAL_MS
    this.logTimer = setInterval(() => {
      this.processLogs(easytier.drainLogLines())
    }, intervalMs)
  }

  private stopLogDrainTimer(): void {
    if (this.logTimer === undefined) {
      return
    }
    clearInterval(this.logTimer)
    this.logTimer = undefined
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
    const now = Date.now()
    if (!this.uiForeground && now - this.lastBackgroundTopologyAt < BACKGROUND_RUNTIME_REFRESH_INTERVAL_MS) {
      return
    }
    if (!this.uiForeground) {
      this.lastBackgroundTopologyAt = now
    }
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
    const now = Date.now()
    if (!this.uiForeground && now - this.lastBackgroundTrafficAt < BACKGROUND_RUNTIME_REFRESH_INTERVAL_MS) {
      return
    }
    if (!this.uiForeground) {
      this.lastBackgroundTrafficAt = now
    }
    this.lastTrafficStatsAt = now
    this.runtimeStateCoordinator.processTrafficStats(stats, fromVpn)
  }

  public ensureRuntimeConnection(): void {
    // Main-process runtime uses the in-process kernel socket service.
  }

  public isVpnExtensionConnected(): boolean {
    return false
  }

  public getRuntimeHealthSummary(now: number = Date.now()): RuntimeHealthSummary {
    const bridge: RuntimeHealthTransportSnapshot = {
      connected: this.initialized,
      connectedAt: this.initializedAt,
      disconnectedAt: 0,
      lastMessageAt: this.lastTrafficStatsAt,
      lastTrafficStatsAt: this.lastTrafficStatsAt
    }
    const runtimeStatsUpdatedAt = AppManager.runtimeStats.snapshotUpdatedAt
    if (!this.hasActiveOrStartingRuntime()) {
      return {
        state: 'stopped',
        text: '实例未运行',
        warning: false,
        checkedAt: now,
        bridge,
        runtimeStatsUpdatedAt
      }
    }
    if (runtimeStatsUpdatedAt <= 0 && bridge.connectedAt > 0 &&
      now - bridge.connectedAt <= RUNTIME_STATS_STALE_AFTER_MS) {
      return {
        state: 'checking',
        text: '正在确认主进程与内核运行状态',
        warning: false,
        checkedAt: now,
        bridge,
        runtimeStatsUpdatedAt
      }
    }
    if (AppManager.runtimeStats.isSnapshotStale(now)) {
      const ageSeconds = runtimeStatsUpdatedAt > 0 ? Math.max(0, Math.trunc((now - runtimeStatsUpdatedAt) / 1000)) : 0
      return {
        state: 'runtime_stats_timeout',
        text: runtimeStatsUpdatedAt > 0 ? `状态不可确认：主进程采样已中断 ${ageSeconds} 秒` :
          '状态不可确认：尚未收到主进程采样',
        warning: true,
        checkedAt: now,
        bridge,
        runtimeStatsUpdatedAt
      }
    }
    const heartbeatReference = this.lastTrafficStatsAt > 0 ? this.lastTrafficStatsAt : bridge.connectedAt
    const heartbeatAgeMs = heartbeatReference > 0 ? now - heartbeatReference : KERNEL_HEARTBEAT_STALE_AFTER_MS + 1
    if (heartbeatAgeMs > KERNEL_HEARTBEAT_STALE_AFTER_MS) {
      return {
        state: 'kernel_timeout',
        text: `状态不可确认：内核响应已超时 ${Math.trunc(heartbeatAgeMs / 1000)} 秒`,
        warning: true,
        checkedAt: now,
        bridge,
        runtimeStatsUpdatedAt
      }
    }
    if (this.lastTrafficStatsAt <= 0) {
      return {
        state: 'checking',
        text: '正在确认内核运行状态',
        warning: false,
        checkedAt: now,
        bridge,
        runtimeStatsUpdatedAt
      }
    }
    return {
      state: 'healthy',
      text: '主进程与内核响应正常',
      warning: false,
      checkedAt: now,
      bridge,
      runtimeStatsUpdatedAt
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

  private async startInternal(uuid: string, _byCard: boolean): Promise<boolean> {
    const config: ConfigJson | undefined = this.getConfig(uuid)
    if (!config) {
      return false
    }
    Logger.debug(`start config requested instance=${uuid}`, this)
    if (!syncWholeConfig(uuid, this.getConfigName(uuid) ?? uuid, config)) {
      Logger.error(`start config sync failed instance=${uuid}`, this)
      return false
    }
    const displayName = this.getConfigName(uuid) ?? uuid
    const started = await this.startMainRuntime(config, displayName, false)
    if (started) {
      if (!this.getRunningInstance(uuid)) {
        this.markOptimisticRunning(config, displayName)
      }
      AppManager.runtimeStats.startLiveRefresh(true)
      this.notifyFavoriteCardChanged()
    }
    Logger.info(`start completed instance=${uuid} result=${started}`, this)
    return started
  }

  private async startMainRuntime(config: ConfigJson, displayName: string, oneShot: boolean): Promise<boolean> {
    const instanceId = (config.instance_id as string | undefined) ?? ''
    if (instanceId.length === 0) {
      return false
    }
    const keepAliveStarted = await requestEntryKeepAliveStart(displayName)
    if (!keepAliveStarted) {
      return false
    }
    if (!config.no_tun) {
      this.needTUN.add(instanceId)
    }
    const request: EntryRuntimeStartRequest = {
      configJson: JSON.stringify(config),
      instanceId,
      displayName,
      oneShot
    }
    const started = await requestEntryRuntimeStart(request)
    if (!started) {
      this.needTUN.delete(instanceId)
      await requestEntryKeepAliveStop()
      Logger.error(`main-process runtime start rejected instance=${instanceId}`, this)
    }
    return started
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
    const started = await this.startMainRuntime(config, name, false)
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

  public startNearbyOneShot(requestId: string, configJson: string): Promise<boolean> {
    let config: ConfigJson
    try {
      config = JSON.parse(configJson) as ConfigJson
    } catch (_) {
      return Promise.resolve(false)
    }
    const instanceId = (config.instance_id as string | undefined) ?? ''
    if (requestId.length === 0 || instanceId.length === 0 || this.hasActiveOrStartingRuntime()) {
      return Promise.resolve(false)
    }
    config.hostname = getHostname()
    const displayName = getHostname()
    this.pendingStartIds.add(instanceId)
    let started = false
    return this.enqueueOperation(async () => {
      started = await this.startMainRuntime(config, displayName, true)
      if (started) {
        this.activeOneShotConfigJson = JSON.stringify(config)
        this.activeOneShotRequestId = requestId
        this.acceptedRuntimeIds.add(instanceId)
        this.markOptimisticRunning(config, displayName)
        AppManager.runtimeStats.startLiveRefresh(true)
        this.notifyFavoriteCardChanged()
      }
    }).then(() => started).catch((error: Error) => {
      Logger.error(`nearby one-shot start failed request=${requestId}: ${error.message}`, this)
      return false
    }).finally(() => {
      this.pendingStartIds.delete(instanceId)
    })
  }

  public async rollbackNearbyOneShot(requestId: string): Promise<void> {
    if (requestId.length === 0 || this.activeOneShotRequestId !== requestId) {
      return
    }
    await this.stopAndWait()
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
    const runtimeIds = this.getRuntimeIntentIds()
    if (runtimeIds.length > 0 && !await requestEntryRuntimeStop(runtimeIds)) {
      throw new Error('main-process runtime stop failed')
    }
    AppManager.runtimeStats.stopLiveRefresh()
    await requestEntryKeepAliveStop()

    // 底层 stop/destroy 全部结束后才清 UI，下一次 start 不会插入旧销毁事务。
    this.runtimeStateCoordinator.clearRunningState()
    this.acceptedRuntimeIds.clear()
    this.activeOneShotConfigJson = ''
    this.activeOneShotRequestId = ''
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

  public restartForNetworkChange(ids: string[], beginVpnRestart: () => Promise<boolean>,
    completeVpnRestart: (started: boolean, stopped: boolean) => Promise<void>): Promise<NetworkRestartResult> {
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
          await completeVpnRestart(false, false)
        }
        return
      }
      try {
        const shouldStart = (): boolean => intentGeneration === this.runtimeIntentGeneration
        result = this.activeOneShotConfigJson.length > 0 ?
          await softRestartOneShotInstance(restartIds[0], this.activeOneShotConfigJson, shouldStart) :
          await softRestartStoredInstances(restartIds, shouldStart)
      } finally {
        const runtimeStillWanted = intentGeneration === this.runtimeIntentGeneration
        await completeVpnRestart(result.started && runtimeStillWanted, result.stopped)
        if (!runtimeStillWanted && result.started) {
          await requestEntryRuntimeStop(restartIds)
          result = {
            stopped: result.stopped,
            started: false,
            cancelled: true
          }
        }
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
