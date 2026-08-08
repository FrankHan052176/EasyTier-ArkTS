import { Context } from '@kit.AbilityKit'
import { JSON, util } from '@kit.ArkTS'
import { BusinessError, deviceInfo } from '@kit.BasicServicesKit'
import { abilityConnectionManager, distributedDeviceManager } from '@kit.DistributedServiceKit'
import easytier from 'easytier-ohrs'
import { AppManager } from '../../AppManager'
import { ConfigFieldValue, ConfigJson } from '../../config/schema/SchemaConfig'
import { RuntimeInstanceState } from '../../types/runtime/RuntimeTypes'
import {
  BACKGROUND_KEEP_ALIVE_TASK_KEEPING,
  normalizeBackgroundKeepAliveMode
} from '../../types/runtime/BackgroundKeepAliveTypes'
import { EventHelper } from '../../util/EventHelper'
import { Logger } from '../../shared/logging/Logger'
import {
  APP_BUNDLE_NAME,
  ENTRY_ABILITY_NAME,
  ENTRY_MODULE_NAME
} from '../runtime/AbilityRuntimePolicy'
import {
  CoreManagementRpcClient,
  CoreNetworkInstanceRunningInfo,
  CoreNetworkMeta,
  CoreUuid,
  coreUuidToString,
  mapCoreRuntimeInstance
} from './CoreManagementRpc'
import {
  RemoteActionSummaryResult,
  RemoteBooleanResult,
  RemoteConfigMeta,
  RemoteCreateDefaultConfigResult,
  RemoteDeviceLite,
  RemoteFieldValueResult,
  RemoteGetConfigResult,
  RemoteGetFieldsResult,
  RemoteRuntimeInstanceLite,
  RemoteSettingsState,
  RemoteSummary
} from './RemoteManageDtos'

const REMOTE_MANAGE_SERVICE_NAME = 'easytier.nearby.core-management.v1'
const REMOTE_MANAGE_PROTOCOL = 'easytier-core-rpc'
const REMOTE_MANAGE_PROTOCOL_VERSION = '1'
const PACKET_PUMP_ACTIVE_INTERVAL_MS = 8
const PACKET_PUMP_IDLE_INTERVAL_MS = 100
const PACKET_PUMP_ACTIVE_EMPTY_ROUNDS = 8
const PRIVATE_SCHEMA_VERSION = 1
const PRIVATE_PACKET_KIND_RPC = 1
const PRIVATE_PACKET_KIND_SETTINGS = 2
const PRIVATE_REQUEST_TIMEOUT_MS = 5000
const HOST_PROXY_RETRY_COUNT = 20
const HOST_PROXY_RETRY_INTERVAL_MS = 100
const MAX_BUFFERED_HOST_RPC_PACKETS = 64
const MAX_REMOTE_MANAGE_HOST_SESSIONS = 8
const MAX_PENDING_PRIVATE_REQUESTS = 32
const MAX_QUEUED_PRIVATE_PACKETS = 32
const MAX_REMOTE_PACKET_BYTES = 64 * 1024
const PRIVATE_OPERATION_GET_SETTINGS = 'get_settings'
const PRIVATE_OPERATION_UPDATE_SETTING = 'update_setting'

export const REMOTE_MANAGE_CONNECTION_EVENT = 'remote_manage_connection'
export const REMOTE_MANAGE_SUMMARY_DIRTY_EVENT = 'remote_manage_summary_dirty'

interface RemoteErrorLike {
  code?: number | string
  message?: string
}

interface RemoteManageConnectParameters extends Record<string, string> {
  protocol: string
  version: string
}

interface RemoteSessionRuntime {
  sessionId: number
  sessionKey: string
  role: 'client' | 'host'
  deviceName: string
  connected: boolean
  closed: boolean
  coreReady: boolean
  corePreparing: boolean
  pendingCorePackets: Uint8Array[]
  appReady: Promise<void>
  privatePacketQueue: Promise<void>
  privatePacketsPending: number
  pumping: boolean
  pumpTimer: number
  pumpDelayMs: number
  pumpEmptyRounds: number
  connectCallback: Callback<abilityConnectionManager.EventCallbackInfo>
  disconnectCallback: Callback<abilityConnectionManager.EventCallbackInfo>
  receiveDataCallback: Callback<abilityConnectionManager.EventCallbackInfo>
}

interface NearbyOhosEnvelope {
  schemaVersion: number
  kind: string
  requestId: string
  operation: string
  payloadJson?: string
  ok?: boolean
  error?: string
}

interface RemoteSettingUpdatePayload {
  key: string
  valueBoolean?: boolean
  valueString?: string
}

class RemotePrivatePendingRequest {
  sessionKey: string
  operation: string
  timer: number
  resolve: (value: string | undefined) => void
  reject: (reason?: Object) => void

  constructor(sessionKey: string, operation: string, timer: number,
    resolve: (value: string | undefined) => void, reject: (reason?: Object) => void) {
    this.sessionKey = sessionKey
    this.operation = operation
    this.timer = timer
    this.resolve = resolve
    this.reject = reject
  }
}

function delay(milliseconds: number): Promise<void> {
  return new Promise<void>((resolve) => {
    setTimeout(resolve, milliseconds)
  })
}

function safeErrorText(error: Object | string | undefined): string {
  if (typeof error === 'string') {
    return error
  }
  if (!error) {
    return 'unknown error'
  }
  if (error instanceof Error && error.message.length > 0) {
    return error.message
  }
  try {
    const raw = error as RemoteErrorLike
    const code = raw.code
    const message = raw.message
    if (message && message.length > 0) {
      return code !== undefined ? `${code}: ${message}` : message
    }
  } catch (_) {
  }
  try {
    return JSON.stringify(error)
  } catch (_) {
    return `${error}`
  }
}

function emptyRemoteSettings(): RemoteSettingsState {
  return {
    ext_mode: false,
    background_keep_alive_mode: '',
    dev: false,
    vpn_routes: false,
    force_global: false,
    dns: '',
    core_log: false,
    debug_log: false,
    distributePerm: false,
    deviceType: '',
    sdkApiVersion: 0
  }
}

class RemoteManageServiceClass {
  private clientConnectGeneration: number = 0
  private clientRuntime: RemoteSessionRuntime | undefined = undefined
  private hostRuntimes: Map<number, RemoteSessionRuntime> = new Map()
  private lastSummary: RemoteSummary | undefined = undefined
  private fieldSaveQueues: Map<string, Promise<void>> = new Map()
  private pendingPrivateRequests: Map<string, RemotePrivatePendingRequest> = new Map()

  listAvailableDevices(deviceManager: distributedDeviceManager.DeviceManager): RemoteDeviceLite[] {
    try {
      const devices = deviceManager.getAvailableDeviceListSync() as distributedDeviceManager.DeviceBasicInfo[]
      return (devices ?? []).map((device) => {
        const item: RemoteDeviceLite = {
          deviceId: device.deviceId,
          networkId: device.networkId,
          deviceName: device.deviceName ?? device.networkId ?? device.deviceId
        }
        return item
      }).filter((device) => (device.networkId ?? '').length > 0)
    } catch (error) {
      Logger.error(`[RemoteManageClient] list devices failed: ${safeErrorText(error as Object)}`, 'RemoteManageService')
      return []
    }
  }

  get connected(): boolean {
    return this.clientRuntime?.connected ?? false
  }

  get currentSessionKey(): string | undefined {
    return this.clientRuntime?.sessionKey
  }

  get currentDeviceName(): string {
    return this.clientRuntime?.deviceName ?? ''
  }

  get cachedSummary(): RemoteSummary | undefined {
    return this.lastSummary
  }

  isCurrentSession(sessionKey: string | undefined): boolean {
    return !!sessionKey && this.clientRuntime?.sessionKey === sessionKey
  }

  getConfigName(configId: string | undefined): string | undefined {
    if (!configId || !this.lastSummary) {
      return undefined
    }
    return this.lastSummary.configs.find((item) => item.configId === configId)?.displayName
  }

  async connect(context: Context, device: RemoteDeviceLite): Promise<RemoteSummary> {
    const generation = ++this.clientConnectGeneration
    this.closeClientRuntime(true)
    const targetDeviceId = device.networkId
    if (!targetDeviceId || targetDeviceId.length === 0) {
      throw new Error('目标设备缺少 networkId')
    }
    const peerInfo: abilityConnectionManager.PeerInfo = {
      deviceId: targetDeviceId,
      bundleName: APP_BUNDLE_NAME,
      moduleName: ENTRY_MODULE_NAME,
      abilityName: ENTRY_ABILITY_NAME,
      serviceName: REMOTE_MANAGE_SERVICE_NAME
    }
    const parameters: RemoteManageConnectParameters = {
      protocol: REMOTE_MANAGE_PROTOCOL,
      version: REMOTE_MANAGE_PROTOCOL_VERSION
    }
    const connectOptions: abilityConnectionManager.ConnectOptions = {
      needSendData: true,
      startOptions: abilityConnectionManager.StartOptionParams.START_IN_FOREGROUND,
      parameters
    }
    let sessionId = -1
    try {
      sessionId = abilityConnectionManager.createAbilityConnectionSession(
        REMOTE_MANAGE_SERVICE_NAME,
        context,
        peerInfo,
        connectOptions
      )
    } catch (error) {
      throw new Error(`创建协同会话失败: ${safeErrorText(error as Object)}`)
    }
    let runtime: RemoteSessionRuntime
    try {
      runtime = this.createRuntime(sessionId, 'client', device.deviceName)
    } catch (error) {
      try {
        abilityConnectionManager.destroyAbilityConnectionSession(sessionId)
      } catch (_) {
      }
      throw new Error(safeErrorText(error as Object))
    }
    if (generation !== this.clientConnectGeneration) {
      this.cleanupRuntime(runtime, true)
      throw new Error('连接请求已取消')
    }
    this.clientRuntime = runtime
    this.registerSessionEvents(runtime)
    try {
      const result = await abilityConnectionManager.connect(sessionId)
      if (generation !== this.clientConnectGeneration || this.clientRuntime?.sessionId !== sessionId) {
        throw new Error('连接请求已被新的会话替换')
      }
      if (!result.isConnected) {
        throw new Error(this.formatConnectFailure(result))
      }
      runtime.connected = true
      await this.flushOutboundPackets(runtime)
      const summary = await this.requestSummary(runtime.sessionKey)
      if (generation !== this.clientConnectGeneration || this.clientRuntime?.sessionId !== sessionId) {
        throw new Error('连接请求已被新的会话替换')
      }
      this.lastSummary = summary
      this.publishClientConnectionState()
      return summary
    } catch (error) {
      this.cleanupRuntime(runtime, true)
      if (this.clientRuntime?.sessionId === sessionId) {
        this.clientRuntime = undefined
        this.lastSummary = undefined
        this.publishClientConnectionState()
      }
      throw new Error(`协同连接失败: ${safeErrorText(error as Object)}`)
    }
  }

  async disconnect(): Promise<void> {
    this.clientConnectGeneration += 1
    this.closeClientRuntime(true)
  }

  destroyHostSessions(): void {
    Array.from(this.hostRuntimes.values()).forEach((runtime) => {
      this.cleanupRuntime(runtime, true)
    })
    this.hostRuntimes.clear()
  }

  handleCollaborate(context: Context, wantParam: Record<string, Object>, appReady: Promise<void>): number {
    const collabParam = wantParam['ohos.extra.param.key.supportCollaborateIndex'] as Record<string, Object>
    if (!collabParam) {
      Logger.error('[RemoteManageHost] missing collaborate param', 'RemoteManageService')
      return 1
    }
    const peerInfo = (collabParam['PeerInfo'] ??
      collabParam['ohos.collaboration.key.peerInfo']) as abilityConnectionManager.PeerInfo
    const connectOptions = (collabParam['ConnectOption'] ??
      collabParam['ohos.collaboration.key.connectOptions']) as abilityConnectionManager.ConnectOptions
    const token = collabParam['ohos.dms.collabToken'] as string
    if (!peerInfo || !connectOptions || typeof token !== 'string' || token.length === 0 ||
      typeof peerInfo.deviceId !== 'string' || peerInfo.deviceId.length === 0 ||
      peerInfo.bundleName !== APP_BUNDLE_NAME ||
      peerInfo.moduleName !== ENTRY_MODULE_NAME || peerInfo.abilityName !== ENTRY_ABILITY_NAME ||
      peerInfo.serviceName !== REMOTE_MANAGE_SERVICE_NAME ||
      connectOptions.needSendData !== true) {
      this.rejectCollaborate(token, 'invalid EasyTier Core management collaboration')
      return 1
    }
    const parameters = connectOptions.parameters
    if (!parameters || parameters['protocol'] !== REMOTE_MANAGE_PROTOCOL ||
      parameters['version'] !== REMOTE_MANAGE_PROTOCOL_VERSION) {
      this.rejectCollaborate(token, 'unsupported EasyTier Core management protocol')
      return 1
    }
    if (this.hostRuntimes.size >= MAX_REMOTE_MANAGE_HOST_SESSIONS) {
      this.rejectCollaborate(token, 'too many EasyTier Core management sessions')
      return 1
    }
    try {
      if (context.filesDir.length === 0 || !easytier.initConfigStore(context.filesDir)) {
        this.rejectCollaborate(token, 'Core config store is unavailable')
        return 1
      }
    } catch (error) {
      this.rejectCollaborate(token, `initialize Core config store failed: ${safeErrorText(error as Object)}`)
      return 1
    }
    let sessionId = -1
    try {
      sessionId = abilityConnectionManager.createAbilityConnectionSession(
        REMOTE_MANAGE_SERVICE_NAME,
        context,
        peerInfo,
        connectOptions
      )
    } catch (error) {
      this.rejectCollaborate(token, `create Core management session failed: ${safeErrorText(error as Object)}`)
      return 1
    }
    let runtime: RemoteSessionRuntime
    try {
      runtime = this.createRuntime(sessionId, 'host', peerInfo.deviceId, appReady)
    } catch (error) {
      try {
        abilityConnectionManager.destroyAbilityConnectionSession(sessionId)
      } catch (_) {
      }
      this.rejectCollaborate(token, safeErrorText(error as Object))
      return 1
    }
    this.hostRuntimes.set(sessionId, runtime)
    this.registerSessionEvents(runtime)
    void this.prepareHostCoreRuntime(context, runtime)
    abilityConnectionManager.acceptConnect(sessionId, token).then(() => {
      if (runtime.closed) {
        return
      }
      runtime.connected = true
      this.schedulePacketPump(runtime, PACKET_PUMP_ACTIVE_INTERVAL_MS)
      Logger.info(`[RemoteManageHost] accepted Core RPC session=${sessionId}`, 'RemoteManageService')
    }).catch((error: BusinessError) => {
      Logger.error(`[RemoteManageHost] accept failed: ${safeErrorText(error)}`, 'RemoteManageService')
      this.hostRuntimes.delete(sessionId)
      this.cleanupRuntime(runtime, true)
    })
    return 0
  }

  async requestSummary(expectedSessionKey?: string): Promise<RemoteSummary> {
    const rpc = this.clientRpc(expectedSessionKey)
    const ids = await rpc.listInstanceIds()
    const metas = await rpc.listInstanceMetas(ids)
    const runningInfo = await rpc.collectNetworkInfo(ids)
    const metaById = new Map<string, CoreNetworkMeta>()
    metas.forEach((meta: CoreNetworkMeta) => {
      if (meta.inst_id) {
        metaById.set(coreUuidToString(meta.inst_id), meta)
      }
    })
    const configs: RemoteConfigMeta[] = []
    const runtimes: RemoteRuntimeInstanceLite[] = []
    let coreVersion = ''
    for (const idValue of ids) {
      const instanceId = coreUuidToString(idValue)
      const meta = metaById.get(instanceId)
      const displayName = meta?.instance_name || meta?.network_name || instanceId
      const info = runningInfo[instanceId]
      const runtime = mapCoreRuntimeInstance(instanceId, displayName, undefined, info)
      if (!coreVersion && info?.my_node_info?.version) {
        coreVersion = info.my_node_info.version
      }
      configs.push({
        configId: instanceId,
        displayName,
        running: runtime.running
      })
      runtimes.push({
        configId: runtime.configId,
        instanceId: runtime.instanceId,
        displayName: runtime.displayName,
        running: runtime.running,
        myNodeInfo: runtime.myNodeInfo,
        peerCount: runtime.peers.length,
        routeCount: runtime.routes.length
      })
    }
    const runningConfigs = runtimes.filter((instance) => instance.running)
    let settings = emptyRemoteSettings()
    try {
      settings = await this.getSettings(expectedSessionKey)
    } catch (error) {
      Logger.warn(`[RemoteManageClient] private settings unavailable: ${safeErrorText(error as Object)}`,
        'RemoteManageService')
    }
    const summary: RemoteSummary = {
      coreVersion,
      deviceName: this.currentDeviceName,
      sdkApiVersion: settings.sdkApiVersion,
      configs,
      runtime: {
        configCount: configs.length,
        runningCount: runningConfigs.length,
        runningConfigs,
        runtimeDurationText: runningConfigs.length > 0 ? 'Core RPC 在线' : '未运行',
        memoryUsageText: 'Core RPC 未提供'
      },
      settings
    }
    if (expectedSessionKey && !this.isCurrentSession(expectedSessionKey)) {
      throw new Error('远端连接已变化，请重新进入页面')
    }
    this.lastSummary = summary
    return summary
  }

  async listConfigs(expectedSessionKey?: string): Promise<RemoteConfigMeta[]> {
    return (await this.requestSummary(expectedSessionKey)).configs
  }

  async getConfig(configId: string, expectedSessionKey?: string): Promise<RemoteGetConfigResult | undefined> {
    const rpc = this.clientRpc(expectedSessionKey)
    const config: ConfigJson | undefined = await rpc.getNetworkConfig(configId)
    if (!config) {
      return undefined
    }
    return {
      configId,
      displayName: this.getConfigName(configId) ?? configId,
      config
    }
  }

  async getRuntimeInstance(configId: string, expectedSessionKey?: string): Promise<RuntimeInstanceState | undefined> {
    const rpc = this.clientRpc(expectedSessionKey)
    const uuid = this.uuidValue(configId)
    const infoMap = await rpc.collectNetworkInfo([uuid])
    const info = infoMap[configId]
    if (!info) {
      return undefined
    }
    return mapCoreRuntimeInstance(configId, this.getConfigName(configId) ?? configId, undefined, info)
  }

  async getConfigFields(configId: string, fields: string[], expectedSessionKey?: string): Promise<RemoteGetFieldsResult> {
    const remote = await this.getConfig(configId, expectedSessionKey)
    const values: RemoteFieldValueResult[] = []
    for (const field of fields) {
      const value: ConfigFieldValue = remote === undefined
        ? undefined
        : remote.config[field] as ConfigFieldValue
      values.push({
        field,
        rawValue: value === undefined ? undefined : JSON.stringify(value),
        found: value !== undefined
      })
    }
    return { values }
  }

  setConfigFieldQueued(configId: string, field: string, value: ConfigFieldValue, expectedSessionKey?: string): void {
    const queueKey = `${expectedSessionKey ?? this.currentSessionKey ?? ''}:${configId}:${field}`
    const previous = this.fieldSaveQueues.get(queueKey) ?? Promise.resolve()
    const next = previous.catch(() => {
    }).then(async () => {
      const remote = await this.getConfig(configId, expectedSessionKey)
      if (!remote) {
        throw new Error('Core 实例配置不存在')
      }
      remote.config[field] = value
      const saved = await this.saveConfig(configId, remote.displayName, remote.config, expectedSessionKey)
      if (!saved) {
        throw new Error('Core 拒绝更新实例配置')
      }
    }).catch((error: Error) => {
      Logger.error(`[RemoteCoreRpc] update field failed config=${configId} field=${field}: ${error.message}`,
        'RemoteManageService')
    })
    this.fieldSaveQueues.set(queueKey, next)
    next.then(() => {
      if (this.fieldSaveQueues.get(queueKey) === next) {
        this.fieldSaveQueues.delete(queueKey)
      }
    })
  }

  async saveConfig(_configId: string, _displayName: string, _config: ConfigJson,
    _expectedSessionKey?: string): Promise<boolean> {
    return false
  }

  async createDefaultConfig(_displayName: string,
    _expectedSessionKey?: string): Promise<RemoteCreateDefaultConfigResult | undefined> {
    return undefined
  }

  async importConfig(_config: ConfigJson, _displayName: string,
    _expectedSessionKey?: string): Promise<RemoteCreateDefaultConfigResult | undefined> {
    return undefined
  }

  async deleteConfig(configId: string, expectedSessionKey?: string): Promise<boolean> {
    const ok = await this.clientRpc(expectedSessionKey).deleteNetworkInstance(configId)
    if (ok) {
      this.removeCachedConfig(configId)
      this.markSummaryDirty()
    }
    return ok
  }

  async renameConfig(_configId: string, _displayName: string, _expectedSessionKey?: string): Promise<boolean> {
    return false
  }

  async startConfig(configId: string, expectedSessionKey?: string): Promise<RemoteActionSummaryResult> {
    const summary = await this.requestSummary(expectedSessionKey)
    const running = summary.runtime.runningConfigs.some((instance) => instance.instanceId === configId)
    return { ok: running, summary }
  }

  async deployConfigOnce(configId: string, config: ConfigJson,
    expectedSessionKey?: string): Promise<RemoteActionSummaryResult> {
    const before = await this.requestSummary(expectedSessionKey)
    if (before.runtime.runningCount > 0) {
      throw new Error('受控设备已有运行实例，请先停止')
    }
    let oneShotConfig: ConfigJson
    oneShotConfig = JSON.parse(JSON.stringify(config)) as ConfigJson
    oneShotConfig.instance_id = configId
    oneShotConfig.hostname = this.currentDeviceName
    const accepted = await this.clientRpc(expectedSessionKey).runNetworkConfig(configId, oneShotConfig)
    const summary = await this.requestSummary(expectedSessionKey)
    const running = summary.runtime.runningConfigs.some((instance) => instance.instanceId === configId)
    return { ok: accepted && running, summary }
  }

  async stopConfig(configId: string, expectedSessionKey?: string): Promise<RemoteActionSummaryResult> {
    const ok = await this.deleteConfig(configId, expectedSessionKey)
    const summary = await this.requestSummary(expectedSessionKey)
    return { ok, summary }
  }

  async exportToml(configId: string, expectedSessionKey?: string): Promise<string | undefined> {
    const config: ConfigJson | undefined = await this.clientRpc(expectedSessionKey).getNetworkConfig(configId)
    if (!config) {
      return undefined
    }
    return this.clientRpc(expectedSessionKey).validateNetworkConfig(config)
  }

  async getSettings(expectedSessionKey?: string): Promise<RemoteSettingsState> {
    const payloadJson = await this.requestPrivate(PRIVATE_OPERATION_GET_SETTINGS, undefined, expectedSessionKey)
    if (!payloadJson) {
      throw new Error('受控端没有返回应用设置')
    }
    return JSON.parse(payloadJson) as RemoteSettingsState
  }

  async setSetting(key: string, value: boolean | string,
    expectedSessionKey?: string): Promise<RemoteSettingsState> {
    const payload: RemoteSettingUpdatePayload = { key }
    if (typeof value === 'boolean') {
      payload.valueBoolean = value
    } else {
      payload.valueString = value
    }
    const payloadJson = await this.requestPrivate(
      PRIVATE_OPERATION_UPDATE_SETTING,
      JSON.stringify(payload),
      expectedSessionKey
    )
    if (!payloadJson) {
      throw new Error('受控端没有返回更新后的设置')
    }
    const settings = JSON.parse(payloadJson) as RemoteSettingsState
    if (this.lastSummary) {
      this.lastSummary.settings = settings
      this.lastSummary.sdkApiVersion = settings.sdkApiVersion
    }
    return settings
  }

  async requestPermission(_kind: string, _expectedSessionKey?: string): Promise<RemoteSettingsState> {
    throw new Error('跨设备会话不能替对端申请 HarmonyOS 权限')
  }

  markSummaryDirty(): void {
    EventHelper.emitterPublish(REMOTE_MANAGE_SUMMARY_DIRTY_EVENT, {
      data: {
        sessionKey: this.currentSessionKey ?? ''
      }
    })
  }

  private clientRpc(expectedSessionKey?: string): CoreManagementRpcClient {
    const runtime = this.clientRuntime
    if (!runtime || !runtime.connected || runtime.closed) {
      throw new Error('远端未连接')
    }
    if (expectedSessionKey && runtime.sessionKey !== expectedSessionKey) {
      throw new Error('远端连接已变化，请重新进入页面')
    }
    return new CoreManagementRpcClient(runtime.sessionKey)
  }

  private uuidValue(configId: string): CoreUuid {
    const compact = configId.replace(/-/g, '')
    if (!/^[0-9a-fA-F]{32}$/.test(compact)) {
      throw new Error(`无效的 Core 实例 ID: ${configId}`)
    }
    return {
      part1: Number.parseInt(compact.substring(0, 8), 16),
      part2: Number.parseInt(compact.substring(8, 16), 16),
      part3: Number.parseInt(compact.substring(16, 24), 16),
      part4: Number.parseInt(compact.substring(24, 32), 16)
    }
  }

  private closeClientRuntime(destroy: boolean): void {
    const runtime = this.clientRuntime
    if (!runtime) {
      return
    }
    this.clientRuntime = undefined
    this.lastSummary = undefined
    try {
      if (runtime.connected) {
        abilityConnectionManager.disconnect(runtime.sessionId)
      }
    } catch (_) {
    }
    this.cleanupRuntime(runtime, destroy)
    this.publishClientConnectionState()
  }

  private createRuntime(sessionId: number, role: 'client' | 'host', deviceName: string,
    appReady: Promise<void> = Promise.resolve()): RemoteSessionRuntime {
    const sessionKey = `${role}:${sessionId}`
    if (role === 'client' && !easytier.openNearbyManagementSession(sessionKey, false)) {
      throw new Error('无法创建 Core 管理 RPC 端点')
    }
    const runtime = {} as RemoteSessionRuntime
    runtime.sessionId = sessionId
    runtime.sessionKey = sessionKey
    runtime.role = role
    runtime.deviceName = deviceName
    runtime.connected = false
    runtime.closed = false
    runtime.coreReady = role === 'client'
    runtime.corePreparing = false
    runtime.pendingCorePackets = []
    runtime.appReady = appReady
    runtime.privatePacketQueue = Promise.resolve()
    runtime.privatePacketsPending = 0
    runtime.pumping = false
    runtime.pumpTimer = -1
    runtime.pumpDelayMs = 0
    runtime.pumpEmptyRounds = PACKET_PUMP_ACTIVE_EMPTY_ROUNDS
    runtime.connectCallback = (callbackInfo: abilityConnectionManager.EventCallbackInfo) => {
      runtime.connected = true
      this.schedulePacketPump(runtime, PACKET_PUMP_ACTIVE_INTERVAL_MS)
      Logger.info(`[RemoteManage] connect role=${role} session=${callbackInfo.sessionId}`, 'RemoteManageService')
    }
    runtime.disconnectCallback = (callbackInfo: abilityConnectionManager.EventCallbackInfo) => {
      Logger.info(`[RemoteManage] disconnect role=${role} session=${callbackInfo.sessionId}`, 'RemoteManageService')
      if (role === 'client' && this.clientRuntime?.sessionId === sessionId) {
        this.clientRuntime = undefined
        this.lastSummary = undefined
        this.publishClientConnectionState()
      }
      if (role === 'host') {
        this.hostRuntimes.delete(sessionId)
      }
      this.cleanupRuntime(runtime, true)
    }
    runtime.receiveDataCallback = (callbackInfo: abilityConnectionManager.EventCallbackInfo) => {
      if (!callbackInfo.data || runtime.closed) {
        return
      }
      const packet = new Uint8Array(callbackInfo.data)
      if (packet.byteLength === 0 || packet.byteLength > MAX_REMOTE_PACKET_BYTES) {
        this.failRuntime(runtime, `invalid packet size: ${packet.byteLength}`)
        return
      }
      const packetKind = easytier.nearbyManagementPacketKind(packet)
      if (packetKind === PRIVATE_PACKET_KIND_SETTINGS) {
        const privatePacket = new Uint8Array(packet.byteLength)
        privatePacket.set(packet)
        if (runtime.role === 'host') {
          if (runtime.privatePacketsPending >= MAX_QUEUED_PRIVATE_PACKETS) {
            Logger.warn(`[RemoteManageHost] private request queue is full session=${runtime.sessionId}`,
              'RemoteManageService')
            return
          }
          runtime.privatePacketsPending += 1
          const operation = runtime.privatePacketQueue.catch(() => {}).then(async () => {
            if (!runtime.closed) {
              await this.handlePrivatePacket(runtime, privatePacket)
            }
          })
          runtime.privatePacketQueue = operation.then(() => {
            runtime.privatePacketsPending -= 1
          }).catch((error: Error) => {
            runtime.privatePacketsPending -= 1
            Logger.error(`[RemoteManageHost] private request failed: ${error.message}`, 'RemoteManageService')
          })
        } else {
          void this.handlePrivatePacket(runtime, privatePacket)
        }
        return
      }
      if (packetKind !== PRIVATE_PACKET_KIND_RPC) {
        this.failRuntime(runtime, 'rejected malformed packet')
        return
      }
      if (runtime.role === 'host' && !runtime.coreReady) {
        if (runtime.pendingCorePackets.length >= MAX_BUFFERED_HOST_RPC_PACKETS) {
          Logger.error(`[RemoteManageHost] Core packet buffer is full session=${runtime.sessionId}`,
            'RemoteManageService')
          return
        }
        const buffered = new Uint8Array(packet.byteLength)
        buffered.set(packet)
        runtime.pendingCorePackets.push(buffered)
        const context = AppManager.content.context
        if (context) {
          void this.prepareHostCoreRuntime(context, runtime)
        }
        return
      }
      this.pushCorePacket(runtime, packet)
    }
    return runtime
  }

  private async prepareHostCoreRuntime(context: Context, runtime: RemoteSessionRuntime): Promise<void> {
    if (runtime.role !== 'host' || runtime.closed || runtime.coreReady || runtime.corePreparing) {
      return
    }
    runtime.corePreparing = true
    try {
      if (!easytier.initConfigStore(context.filesDir) || !easytier.startNearbyManagementHost() || runtime.closed) {
        throw new Error('主进程 Core 管理宿主未就绪')
      }
      for (let retry = 0; retry < HOST_PROXY_RETRY_COUNT && !runtime.closed; retry++) {
        if (easytier.openNearbyManagementSession(runtime.sessionKey, true)) {
          runtime.coreReady = true
          this.flushBufferedCorePackets(runtime)
          await this.flushOutboundPackets(runtime)
          return
        }
        await delay(HOST_PROXY_RETRY_INTERVAL_MS)
      }
      throw new Error('Core 管理宿主连接超时')
    } catch (error) {
      Logger.error(`[RemoteManageHost] prepare Core host failed session=${runtime.sessionId}: ` +
        safeErrorText(error as Object), 'RemoteManageService')
      this.hostRuntimes.delete(runtime.sessionId)
      this.cleanupRuntime(runtime, true)
    } finally {
      runtime.corePreparing = false
    }
  }

  private flushBufferedCorePackets(runtime: RemoteSessionRuntime): void {
    if (!runtime.coreReady || runtime.closed) {
      return
    }
    const packets = runtime.pendingCorePackets.splice(0, runtime.pendingCorePackets.length)
    for (const packet of packets) {
      if (!this.pushCorePacket(runtime, packet)) {
        break
      }
    }
  }

  private pushCorePacket(runtime: RemoteSessionRuntime, packet: Uint8Array): boolean {
    const accepted = easytier.pushNearbyManagementPacket(runtime.sessionKey, packet)
    if (!accepted) {
      this.failRuntime(runtime, 'Core rejected packet')
      return false
    }
    runtime.pumpEmptyRounds = 0
    this.schedulePacketPump(runtime, PACKET_PUMP_ACTIVE_INTERVAL_MS)
    return true
  }

  private async handlePrivatePacket(runtime: RemoteSessionRuntime, packet: Uint8Array): Promise<void> {
    const raw = easytier.decodeNearbyOhosPacket(packet)
    if (!raw) {
      Logger.warn(`[RemoteManage] private packet decode failed session=${runtime.sessionId}`, 'RemoteManageService')
      return
    }
    let envelope: NearbyOhosEnvelope
    try {
      envelope = JSON.parse(raw) as NearbyOhosEnvelope
    } catch (_) {
      return
    }
    if (runtime.role === 'host' && envelope.kind === 'request') {
      await this.handlePrivateHostRequest(runtime, envelope)
      return
    }
    if (runtime.role === 'client' && envelope.kind === 'response') {
      this.handlePrivateClientResponse(runtime, envelope)
      return
    }
    Logger.warn(`[RemoteManage] private packet role mismatch session=${runtime.sessionId}`, 'RemoteManageService')
  }

  private async handlePrivateHostRequest(runtime: RemoteSessionRuntime, request: NearbyOhosEnvelope): Promise<void> {
    let payloadJson: string | undefined = undefined
    let error: string | undefined = undefined
    try {
      await runtime.appReady
      if (request.operation === PRIVATE_OPERATION_GET_SETTINGS) {
        payloadJson = JSON.stringify(this.readHostSettings())
      } else if (request.operation === PRIVATE_OPERATION_UPDATE_SETTING) {
        if (!request.payloadJson) {
          throw new Error('设置请求缺少载荷')
        }
        const update = JSON.parse(request.payloadJson) as RemoteSettingUpdatePayload
        this.applyHostSetting(update)
        payloadJson = JSON.stringify(this.readHostSettings())
      } else {
        throw new Error('不支持的 HarmonyOS 私有设置操作')
      }
    } catch (caught) {
      error = safeErrorText(caught as Object)
    }
    const response: NearbyOhosEnvelope = {
      schemaVersion: PRIVATE_SCHEMA_VERSION,
      kind: 'response',
      requestId: request.requestId,
      operation: request.operation,
      payloadJson,
      ok: error === undefined,
      error
    }
    try {
      await this.sendPrivateEnvelope(runtime, response)
    } catch (sendError) {
      Logger.error(`[RemoteManageHost] private response failed: ${safeErrorText(sendError as Object)}`,
        'RemoteManageService')
    }
  }

  private handlePrivateClientResponse(runtime: RemoteSessionRuntime, response: NearbyOhosEnvelope): void {
    const pending = this.pendingPrivateRequests.get(response.requestId)
    if (!pending || pending.sessionKey !== runtime.sessionKey) {
      return
    }
    this.pendingPrivateRequests.delete(response.requestId)
    clearTimeout(pending.timer)
    if (pending.operation !== response.operation) {
      pending.reject(new Error('受控端设置响应操作不匹配'))
      return
    }
    if (response.ok !== true) {
      pending.reject(new Error(response.error ?? '受控端拒绝设置请求'))
      return
    }
    pending.resolve(response.payloadJson)
  }

  private readHostSettings(): RemoteSettingsState {
    return {
      ext_mode: false,
      background_keep_alive_mode: AppManager.uiState.background_keep_alive_mode,
      dev: AppManager.uiState.dev,
      vpn_routes: AppManager.uiState.vpn_routes,
      force_global: AppManager.uiState.force_global,
      dns: AppManager.uiState.dns,
      core_log: AppManager.uiState.core_log,
      debug_log: AppManager.uiState.debug_log,
      distributePerm: AppManager.permission.isGetDistributePerm(),
      deviceType: deviceInfo.deviceType,
      sdkApiVersion: deviceInfo.sdkApiVersion
    }
  }

  private applyHostSetting(update: RemoteSettingUpdatePayload): void {
    if (AppManager.easytier.hasActiveOrStartingRuntime()) {
      throw new Error('受控设备运行中，请停止实例后再修改设置')
    }
    const key = update.key
    if (key === 'background_keep_alive_mode') {
      if (update.valueString === undefined) {
        throw new Error('保活模式值无效')
      }
      const mode = normalizeBackgroundKeepAliveMode(update.valueString)
      if (mode === BACKGROUND_KEEP_ALIVE_TASK_KEEPING && deviceInfo.deviceType.toLowerCase() !== 'tablet') {
        throw new Error('计算任务保活仅支持平板设备')
      }
      AppManager.uiState.background_keep_alive_mode = mode
      return
    }
    if (key === 'dns') {
      const dns = update.valueString?.trim() ?? ''
      if (dns.length === 0 || dns.length > 253 || /[\u0000-\u001f\u007f]/.test(dns)) {
        throw new Error('DNS 设置无效')
      }
      AppManager.uiState.dns = dns
      return
    }
    if (update.valueBoolean === undefined) {
      throw new Error('布尔设置值无效')
    }
    if (key === 'dev') {
      AppManager.uiState.dev = update.valueBoolean
    } else if (key === 'vpn_routes') {
      AppManager.uiState.vpn_routes = update.valueBoolean
    } else if (key === 'force_global') {
      AppManager.uiState.force_global = update.valueBoolean
    } else if (key === 'core_log') {
      AppManager.uiState.core_log = update.valueBoolean
    } else if (key === 'debug_log') {
      AppManager.uiState.debug_log = update.valueBoolean
    } else {
      throw new Error('不支持的远端设置项')
    }
  }

  private requestPrivate(operation: string, payloadJson: string | undefined,
    expectedSessionKey?: string): Promise<string | undefined> {
    const runtime = this.clientRuntime
    if (!runtime || !runtime.connected || runtime.closed) {
      return Promise.reject(new Error('远端未连接'))
    }
    if (expectedSessionKey && expectedSessionKey !== runtime.sessionKey) {
      return Promise.reject(new Error('远端连接已变化，请重新进入页面'))
    }
    if (this.pendingPrivateRequests.size >= MAX_PENDING_PRIVATE_REQUESTS) {
      return Promise.reject(new Error('受控端设置请求过多，请稍后重试'))
    }
    const requestId = util.generateRandomUUID().toLowerCase()
    const request: NearbyOhosEnvelope = {
      schemaVersion: PRIVATE_SCHEMA_VERSION,
      kind: 'request',
      requestId,
      operation,
      payloadJson
    }
    return new Promise<string | undefined>((resolve, reject) => {
      const timer = setTimeout(() => {
        const pending = this.pendingPrivateRequests.get(requestId)
        if (!pending) {
          return
        }
        this.pendingPrivateRequests.delete(requestId)
        pending.reject(new Error('受控端设置请求超时'))
      }, PRIVATE_REQUEST_TIMEOUT_MS)
      this.pendingPrivateRequests.set(requestId,
        new RemotePrivatePendingRequest(runtime.sessionKey, operation, timer, resolve, reject))
      this.sendPrivateEnvelope(runtime, request).catch((error: Error) => {
        const pending = this.pendingPrivateRequests.get(requestId)
        if (!pending) {
          return
        }
        this.pendingPrivateRequests.delete(requestId)
        clearTimeout(pending.timer)
        pending.reject(error)
      })
    })
  }

  private async sendPrivateEnvelope(runtime: RemoteSessionRuntime, envelope: NearbyOhosEnvelope): Promise<void> {
    if (runtime.closed || !runtime.connected) {
      throw new Error('跨端会话已断开')
    }
    const encoded = easytier.encodeNearbyOhosPacket(JSON.stringify(envelope)) as Uint8Array | undefined
    if (!encoded) {
      throw new Error('HarmonyOS 私有设置包编码失败')
    }
    const data = new Uint8Array(encoded.byteLength)
    data.set(encoded)
    await this.sendSessionData(runtime, data)
  }

  private async sendSessionData(runtime: RemoteSessionRuntime, data: Uint8Array): Promise<void> {
    if (data.byteLength === 0 || data.byteLength > MAX_REMOTE_PACKET_BYTES) {
      this.failRuntime(runtime, `invalid outbound packet size: ${data.byteLength}`)
      throw new Error('跨端数据包大小无效')
    }
    try {
      await abilityConnectionManager.sendData(runtime.sessionId, data.buffer)
    } catch (error) {
      const reason = `sendData failed: ${safeErrorText(error as Object)}`
      this.failRuntime(runtime, reason)
      throw new Error(reason)
    }
  }

  private registerSessionEvents(runtime: RemoteSessionRuntime): void {
    abilityConnectionManager.on('connect', runtime.sessionId, runtime.connectCallback)
    abilityConnectionManager.on('disconnect', runtime.sessionId, runtime.disconnectCallback)
    abilityConnectionManager.on('receiveData', runtime.sessionId, runtime.receiveDataCallback)
  }

  private cleanupRuntime(runtime: RemoteSessionRuntime, destroy: boolean): void {
    if (runtime.closed) {
      return
    }
    runtime.closed = true
    runtime.connected = false
    runtime.pendingCorePackets = []
    this.rejectPrivateRequests(runtime.sessionKey, '跨端会话已断开')
    if (runtime.pumpTimer >= 0) {
      clearTimeout(runtime.pumpTimer)
      runtime.pumpTimer = -1
      runtime.pumpDelayMs = 0
    }
    try {
      abilityConnectionManager.off('connect', runtime.sessionId, runtime.connectCallback)
    } catch (_) {
    }
    try {
      abilityConnectionManager.off('disconnect', runtime.sessionId, runtime.disconnectCallback)
    } catch (_) {
    }
    try {
      abilityConnectionManager.off('receiveData', runtime.sessionId, runtime.receiveDataCallback)
    } catch (_) {
    }
    easytier.closeNearbyManagementSession(runtime.sessionKey)
    runtime.coreReady = false
    if (destroy) {
      try {
        abilityConnectionManager.destroyAbilityConnectionSession(runtime.sessionId)
      } catch (_) {
      }
    }
  }

  private failRuntime(runtime: RemoteSessionRuntime, reason: string): void {
    if (runtime.closed) {
      return
    }
    Logger.error(`[RemoteManage] closing invalid session=${runtime.sessionId}: ${reason}`, 'RemoteManageService')
    if (runtime.role === 'client' && this.clientRuntime?.sessionId === runtime.sessionId) {
      this.clientRuntime = undefined
      this.lastSummary = undefined
      this.publishClientConnectionState()
    } else if (runtime.role === 'host') {
      this.hostRuntimes.delete(runtime.sessionId)
    }
    try {
      if (runtime.connected) {
        abilityConnectionManager.disconnect(runtime.sessionId)
      }
    } catch (_) {
    }
    this.cleanupRuntime(runtime, true)
  }

  private rejectPrivateRequests(sessionKey: string, reason: string): void {
    const requestIds: string[] = []
    this.pendingPrivateRequests.forEach((pending: RemotePrivatePendingRequest, requestId: string) => {
      if (pending.sessionKey === sessionKey) {
        requestIds.push(requestId)
      }
    })
    for (const requestId of requestIds) {
      const pending = this.pendingPrivateRequests.get(requestId)
      if (!pending) {
        continue
      }
      this.pendingPrivateRequests.delete(requestId)
      clearTimeout(pending.timer)
      pending.reject(new Error(reason))
    }
  }

  private async flushOutboundPackets(runtime: RemoteSessionRuntime): Promise<void> {
    if (runtime.closed || runtime.pumping || !runtime.connected || !runtime.coreReady) {
      return
    }
    runtime.pumping = true
    let packetCount = 0
    try {
      const packets = easytier.drainNearbyManagementPackets(runtime.sessionKey)
      packetCount = packets.length
      for (const packet of packets) {
        if (runtime.closed || !runtime.connected) {
          return
        }
        const data = new Uint8Array(packet.byteLength)
        data.set(packet)
        await this.sendSessionData(runtime, data)
      }
    } catch (error) {
      Logger.error(`[RemoteManage] Core packet pump failed: ${safeErrorText(error as Object)}`, 'RemoteManageService')
    } finally {
      runtime.pumping = false
      if (!runtime.closed && runtime.connected && runtime.coreReady) {
        if (packetCount > 0) {
          runtime.pumpEmptyRounds = 0
        } else if (runtime.pumpEmptyRounds < PACKET_PUMP_ACTIVE_EMPTY_ROUNDS) {
          runtime.pumpEmptyRounds += 1
        }
        const delayMs = runtime.pumpEmptyRounds < PACKET_PUMP_ACTIVE_EMPTY_ROUNDS
          ? PACKET_PUMP_ACTIVE_INTERVAL_MS
          : PACKET_PUMP_IDLE_INTERVAL_MS
        this.schedulePacketPump(runtime, delayMs)
      }
    }
  }

  private schedulePacketPump(runtime: RemoteSessionRuntime, delayMs: number): void {
    if (runtime.closed || !runtime.connected || !runtime.coreReady) {
      return
    }
    if (runtime.pumpTimer >= 0) {
      if (runtime.pumpDelayMs <= delayMs) {
        return
      }
      clearTimeout(runtime.pumpTimer)
      runtime.pumpTimer = -1
    }
    runtime.pumpDelayMs = delayMs
    runtime.pumpTimer = setTimeout(() => {
      runtime.pumpTimer = -1
      runtime.pumpDelayMs = 0
      void this.flushOutboundPackets(runtime)
    }, delayMs)
  }

  private rejectCollaborate(token: string | undefined, reason: string): void {
    Logger.error(`[RemoteManageHost] ${reason}`, 'RemoteManageService')
    if (!token) {
      return
    }
    try {
      abilityConnectionManager.reject(token, reason)
    } catch (_) {
    }
  }

  private formatConnectFailure(result: abilityConnectionManager.ConnectResult): string {
    if (result.reason && result.reason.length > 0) {
      return result.reason
    }
    switch (result.errorCode) {
      case 0:
        return '应用之间已存在连接会话'
      case 1:
        return '对端拒绝协同请求'
      case 2:
        return '本端 Wi-Fi 未开启'
      case 3:
        return '对端 Wi-Fi 未开启'
      case 4:
        return '对端未实现协同入口，请确认 EasyTier 版本'
      case 5:
        return '系统内部错误，请检查对端版本、协同权限与系统协同能力'
      default:
        return `未知连接错误 ${result.errorCode ?? 'unknown'}`
    }
  }

  private removeCachedConfig(configId: string): void {
    if (!this.lastSummary) {
      return
    }
    this.lastSummary.configs = this.lastSummary.configs.filter((item) => item.configId !== configId)
    this.lastSummary.runtime.runningConfigs = this.lastSummary.runtime.runningConfigs.filter((item) => {
      return item.configId !== configId && item.instanceId !== configId
    })
    this.lastSummary.runtime.configCount = this.lastSummary.configs.length
    this.lastSummary.runtime.runningCount = this.lastSummary.runtime.runningConfigs.length
  }

  private publishClientConnectionState(): void {
    EventHelper.emitterPublish(REMOTE_MANAGE_CONNECTION_EVENT, {
      data: {
        connected: this.connected,
        sessionKey: this.currentSessionKey ?? '',
        deviceName: this.currentDeviceName
      }
    })
  }
}

export const RemoteManageService = new RemoteManageServiceClass()
