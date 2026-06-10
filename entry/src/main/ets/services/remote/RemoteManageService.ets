import { Context } from '@kit.AbilityKit'
import { BusinessError } from '@kit.BasicServicesKit'
import { JSON } from '@kit.ArkTS'
import { abilityConnectionManager, distributedDeviceManager } from '@kit.DistributedServiceKit'
import { Logger } from '../../shared/logging/Logger'
import { EventHelper } from '../../util/EventHelper'
import { ConfigFieldValue, ConfigJson } from '../../config/schema/SchemaConfig'
import { RuntimeInstanceState } from '../../types/runtime/RuntimeTypes'
import {
  REMOTE_MANAGE_PROTOCOL_VERSION,
  REMOTE_MANAGE_SERVICE_NAME,
  RemoteActionSummaryResult,
  RemoteBooleanResult,
  RemoteConfigIdPayload,
  RemoteConfigMeta,
  RemoteConnectParameters,
  RemoteCreateDefaultConfigResult,
  RemoteDeviceLite,
  RemoteDisplayNamePayload,
  RemoteExportTomlResult,
  RemoteGetConfigResult,
  RemoteGetFieldsResult,
  RemoteGetFieldsPayload,
  RemoteHostHandler,
  RemoteImportConfigPayload,
  RemoteListConfigsResult,
  RemotePermissionPayload,
  RemoteRenameConfigPayload,
  RemoteRpcNotify,
  RemoteRpcRequest,
  RemoteRpcResponse,
  RemoteSaveConfigPayload,
  RemoteSettingsState,
  RemoteSetConfigFieldPayload,
  RemoteSetSettingPayload,
  RemoteSummary,
  RemoteWireFrame
} from './RemoteManageTypes'

const REMOTE_SEND_MESSAGE_MAX_BYTES = 1024
const REMOTE_FRAME_MAX_BYTES = 900
const REMOTE_MAX_PACKET_CHUNKS = 2048
const REMOTE_INCOMING_MAX_PACKETS = 8
const REMOTE_INCOMING_PACKET_TTL_MS = 15000
const REMOTE_RPC_TIMEOUT_MS = 12000
const REMOTE_BUNDLE_NAME = 'top.frankhan.easytier'
const REMOTE_MODULE_NAME = 'entry'
const REMOTE_ABILITY_NAME = 'EntryAbility'
const REMOTE_NOTIFY_SUMMARY_DIRTY = 'summaryDirty'

export const REMOTE_MANAGE_CONNECTION_EVENT = 'remote_manage_connection'
export const REMOTE_MANAGE_SUMMARY_DIRTY_EVENT = 'remote_manage_summary_dirty'

interface RemotePendingRequest {
  resolve: (payloadJson: string | undefined) => void
  reject: (error: Error) => void
  timer: number
}

interface RemoteIncomingPacket {
  total: number
  chunks: string[]
  received: number
  createdAt: number
}

interface RemoteErrorLike {
  code?: number | string
  message?: string
}

interface RemoteSessionRuntime {
  sessionId: number
  role: 'client' | 'host'
  deviceName: string
  connected: boolean
  hostLifecycleActive: boolean
  pending: Map<string, RemotePendingRequest>
  incoming: Map<string, RemoteIncomingPacket>
  connectCallback: Callback<abilityConnectionManager.EventCallbackInfo>
  disconnectCallback: Callback<abilityConnectionManager.EventCallbackInfo>
  receiveMessageCallback: Callback<abilityConnectionManager.EventCallbackInfo>
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

function utf8ByteLength(text: string): number {
  let bytes = 0
  for (let index = 0; index < text.length; index++) {
    const code = text.charCodeAt(index)
    if (code < 0x80) {
      bytes += 1
    } else if (code < 0x800) {
      bytes += 2
    } else if (code >= 0xD800 && code <= 0xDBFF && index + 1 < text.length) {
      const next = text.charCodeAt(index + 1)
      if (next >= 0xDC00 && next <= 0xDFFF) {
        bytes += 4
        index += 1
      } else {
        bytes += 3
      }
    } else {
      bytes += 3
    }
  }
  return bytes
}

class RemoteManageServiceClass {
  private requestSeq: number = 0
  private packetSeq: number = 0
  private clientConnectGeneration: number = 0
  private clientRuntime: RemoteSessionRuntime | undefined = undefined
  private hostRuntimes: Map<number, RemoteSessionRuntime> = new Map()
  private hostHandlerProvider: (() => RemoteHostHandler) | undefined = undefined
  private lastSummary: RemoteSummary | undefined = undefined
  private fieldSaveQueues: Map<string, Promise<void>> = new Map()
  private hostSummaryDirtyNotifyTimer: number = -1

  setHostHandlerProvider(provider: () => RemoteHostHandler): void {
    this.hostHandlerProvider = provider
  }

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
    return this.clientRuntime ? `${this.clientRuntime.sessionId}` : undefined
  }

  get currentDeviceName(): string {
    return this.clientRuntime?.deviceName ?? ''
  }

  isCurrentSession(sessionKey: string | undefined): boolean {
    if (!sessionKey || !this.clientRuntime) {
      return false
    }
    return `${this.clientRuntime.sessionId}` === sessionKey
  }

  get cachedSummary(): RemoteSummary | undefined {
    return this.lastSummary
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
      bundleName: REMOTE_BUNDLE_NAME,
      moduleName: REMOTE_MODULE_NAME,
      abilityName: REMOTE_ABILITY_NAME,
      serviceName: REMOTE_MANAGE_SERVICE_NAME
    }
    const parameterModel = new RemoteConnectParameters()
    parameterModel.protocol = REMOTE_MANAGE_SERVICE_NAME
    parameterModel.version = `${REMOTE_MANAGE_PROTOCOL_VERSION}`
    const parameters = JSON.parse(JSON.stringify(parameterModel)) as Record<string, string>
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
    const runtime = this.createRuntime(sessionId, 'client', device.deviceName)
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
      const summary = await this.requestSummary(`${sessionId}`)
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

  destroyHostSessions(): void {
    Array.from(this.hostRuntimes.values()).forEach((runtime) => {
      this.cleanupRuntime(runtime, true)
    })
    this.hostRuntimes.clear()
  }

  handleCollaborate(context: Context, wantParam: Record<string, Object>): number {
    const collabParam = wantParam['ohos.extra.param.key.supportCollaborateIndex'] as Record<string, Object>
    if (!collabParam) {
      Logger.error('[RemoteManageHost] missing collaborate param', 'RemoteManageService')
      return 1
    }
    const peerInfo = (collabParam['PeerInfo'] ?? collabParam['ohos.collaboration.key.peerInfo']) as abilityConnectionManager.PeerInfo
    const connectOptions = (collabParam['ConnectOption'] ??
      collabParam['ohos.collaboration.key.connectOptions']) as abilityConnectionManager.ConnectOptions
    const token = collabParam['ohos.dms.collabToken'] as string
    if (!peerInfo || !connectOptions || !token) {
      Logger.error('[RemoteManageHost] invalid collaborate param', 'RemoteManageService')
      try {
        if (token) {
          abilityConnectionManager.reject(token, 'invalid EasyTier remote manage param')
        }
      } catch (_) {
      }
      return 1
    }
    const parameters = connectOptions.parameters
    if (!parameters || parameters['protocol'] !== REMOTE_MANAGE_SERVICE_NAME ||
      parameters['version'] !== `${REMOTE_MANAGE_PROTOCOL_VERSION}`) {
      Logger.error('[RemoteManageHost] unsupported remote manage protocol', 'RemoteManageService')
      try {
        abilityConnectionManager.reject(token, 'unsupported EasyTier remote manage protocol')
      } catch (_) {
      }
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
      const reason = `create EasyTier remote manage session failed: ${safeErrorText(error as Object)}`
      Logger.error(`[RemoteManageHost] ${reason}`, 'RemoteManageService')
      try {
        abilityConnectionManager.reject(token, reason)
      } catch (_) {
      }
      return 1
    }
    const runtime = this.createRuntime(sessionId, 'host', peerInfo.deviceId)
    this.hostRuntimes.set(sessionId, runtime)
    this.registerSessionEvents(runtime)
    abilityConnectionManager.acceptConnect(sessionId, token).then(() => {
      runtime.connected = true
      this.notifyHostConnected(runtime)
      Logger.info(`[RemoteManageHost] accepted session=${sessionId}`, 'RemoteManageService')
    }).catch((error: BusinessError) => {
      Logger.error(`[RemoteManageHost] accept failed: ${safeErrorText(error)}`, 'RemoteManageService')
      this.hostRuntimes.delete(sessionId)
      this.cleanupRuntime(runtime, true)
    })
    return 0
  }

  async requestSummary(expectedSessionKey?: string): Promise<RemoteSummary> {
    const payload = this.parseResponse<RemoteSummary>(await this.request('summary', undefined, expectedSessionKey))
    if (!payload) {
      throw new Error('远端状态为空')
    }
    if (expectedSessionKey && !this.isCurrentSession(expectedSessionKey)) {
      throw new Error('远端连接已变化，请重新进入页面')
    }
    this.lastSummary = payload
    return this.lastSummary
  }

  async listConfigs(expectedSessionKey?: string): Promise<RemoteConfigMeta[]> {
    const payload = this.parseResponse<RemoteListConfigsResult>(await this.request('listConfigs', undefined, expectedSessionKey))
    return payload?.configs ?? []
  }

  async getConfig(configId: string, expectedSessionKey?: string): Promise<RemoteGetConfigResult | undefined> {
    const requestPayload: RemoteConfigIdPayload = { configId }
    return this.parseResponse<RemoteGetConfigResult>(
      await this.request('getConfig', this.stringifyPayload(requestPayload), expectedSessionKey)
    )
  }

  async getRuntimeInstance(configId: string, expectedSessionKey?: string): Promise<RuntimeInstanceState | undefined> {
    const requestPayload: RemoteConfigIdPayload = { configId }
    return this.parseResponse<RuntimeInstanceState>(
      await this.request('getRuntimeInstance', this.stringifyPayload(requestPayload), expectedSessionKey)
    )
  }

  async getConfigFields(configId: string, fields: string[], expectedSessionKey?: string): Promise<RemoteGetFieldsResult> {
    const requestPayload: RemoteGetFieldsPayload = { configId, fields }
    const payload = this.parseResponse<RemoteGetFieldsResult>(
      await this.request('getConfigFields', this.stringifyPayload(requestPayload), expectedSessionKey)
    )
    if (!payload) {
      throw new Error('远端字段响应为空')
    }
    return payload
  }

  setConfigFieldQueued(configId: string, field: string, value: ConfigFieldValue, expectedSessionKey?: string): void {
    const requestPayload: RemoteSetConfigFieldPayload = {
      configId,
      field,
      value
    }
    const queueKey = `${expectedSessionKey ?? this.currentSessionKey ?? ''}:${configId}:${field}`
    const previous = this.fieldSaveQueues.get(queueKey) ?? Promise.resolve()
    const next = previous.catch(() => {
    }).then(async () => {
      const payloadJson = await this.request('setConfigField', this.stringifyPayload(requestPayload), expectedSessionKey)
      const payload = this.parseResponse<RemoteBooleanResult>(payloadJson)
      if (!payload?.ok) {
        Logger.error(`[RemoteEditSession] remote edit save rejected config=${configId} field=${field}`,
          'RemoteManageService')
      }
    }).catch((error: Error) => {
      Logger.error(`[RemoteEditSession] remote edit save failed config=${configId} field=${field}: ${error.message}`,
        'RemoteManageService')
    })
    this.fieldSaveQueues.set(queueKey, next)
    next.then(() => {
      if (this.fieldSaveQueues.get(queueKey) === next) {
        this.fieldSaveQueues.delete(queueKey)
      }
    })
  }

  async saveConfig(configId: string, displayName: string, config: ConfigJson, expectedSessionKey?: string): Promise<boolean> {
    const requestPayload: RemoteSaveConfigPayload = { configId, displayName, config }
    const payload = this.parseResponse<RemoteBooleanResult>(
      await this.request('saveConfig', this.stringifyPayload(requestPayload), expectedSessionKey)
    )
    const ok = payload?.ok ?? false
    if (ok) {
      this.markSummaryDirty()
    }
    return ok
  }

  async createDefaultConfig(displayName: string, expectedSessionKey?: string): Promise<RemoteCreateDefaultConfigResult | undefined> {
    const requestPayload: RemoteDisplayNamePayload = { displayName }
    const result = this.parseResponse<RemoteCreateDefaultConfigResult>(
      await this.request('createDefaultConfig', this.stringifyPayload(requestPayload), expectedSessionKey)
    )
    if (result) {
      this.markSummaryDirty()
    }
    return result
  }

  async importConfig(config: ConfigJson, displayName: string,
    expectedSessionKey?: string): Promise<RemoteCreateDefaultConfigResult | undefined> {
    const requestPayload: RemoteImportConfigPayload = { config, displayName }
    const result = this.parseResponse<RemoteCreateDefaultConfigResult>(
      await this.request('importConfig', this.stringifyPayload(requestPayload), expectedSessionKey)
    )
    if (result) {
      this.markSummaryDirty()
    }
    return result
  }

  async deleteConfig(configId: string, expectedSessionKey?: string): Promise<boolean> {
    const requestPayload: RemoteConfigIdPayload = { configId }
    const payload = this.parseResponse<RemoteBooleanResult>(
      await this.request('deleteConfig', this.stringifyPayload(requestPayload), expectedSessionKey)
    )
    const ok = payload?.ok ?? false
    if (ok) {
      this.removeCachedConfig(configId)
      this.markSummaryDirty()
    }
    return ok
  }

  async renameConfig(configId: string, displayName: string, expectedSessionKey?: string): Promise<boolean> {
    const requestPayload: RemoteRenameConfigPayload = { configId, displayName }
    const payload = this.parseResponse<RemoteBooleanResult>(
      await this.request('renameConfig', this.stringifyPayload(requestPayload), expectedSessionKey)
    )
    const ok = payload?.ok ?? false
    if (ok) {
      this.updateCachedConfigName(configId, displayName)
      this.markSummaryDirty()
    }
    return ok
  }

  async startConfig(configId: string, expectedSessionKey?: string): Promise<RemoteActionSummaryResult> {
    const requestPayload: RemoteConfigIdPayload = { configId }
    const payload = this.parseResponse<RemoteActionSummaryResult>(
      await this.request('startConfig', this.stringifyPayload(requestPayload), expectedSessionKey)
    )
    if (payload?.summary) {
      this.lastSummary = payload.summary
    }
    if (payload?.ok) {
      this.markSummaryDirty()
    }
    return payload ?? { ok: false }
  }

  async stopConfig(configId: string, expectedSessionKey?: string): Promise<RemoteActionSummaryResult> {
    const requestPayload: RemoteConfigIdPayload = { configId }
    const payload = this.parseResponse<RemoteActionSummaryResult>(
      await this.request('stopConfig', this.stringifyPayload(requestPayload), expectedSessionKey)
    )
    if (payload?.summary) {
      this.lastSummary = payload.summary
    }
    if (payload?.ok) {
      this.markSummaryDirty()
    }
    return payload ?? { ok: false }
  }

  async exportToml(configId: string, expectedSessionKey?: string): Promise<string | undefined> {
    const requestPayload: RemoteConfigIdPayload = { configId }
    const payload = this.parseResponse<RemoteExportTomlResult>(
      await this.request('exportToml', this.stringifyPayload(requestPayload), expectedSessionKey)
    )
    return payload?.toml
  }

  async getSettings(expectedSessionKey?: string): Promise<RemoteSettingsState> {
    const payload = this.parseResponse<RemoteSettingsState>(await this.request('getSettings', undefined, expectedSessionKey))
    if (!payload) {
      throw new Error('远端设置为空')
    }
    return payload
  }

  async setSetting(key: string, value: boolean | string, expectedSessionKey?: string): Promise<RemoteSettingsState> {
    const requestPayload: RemoteSetSettingPayload = {
      key,
      valueBoolean: typeof value === 'boolean' ? value : undefined,
      valueString: typeof value === 'string' ? value : undefined
    }
    const payload = this.parseResponse<RemoteSettingsState>(
      await this.request('setSetting', this.stringifyPayload(requestPayload), expectedSessionKey)
    )
    if (!payload) {
      throw new Error('远端设置为空')
    }
    this.updateCachedSettings(payload)
    this.markSummaryDirty()
    return payload
  }

  async requestPermission(kind: string, expectedSessionKey?: string): Promise<RemoteSettingsState> {
    const requestPayload: RemotePermissionPayload = { kind }
    const payload = this.parseResponse<RemoteSettingsState>(
      await this.request('requestPermission', this.stringifyPayload(requestPayload), expectedSessionKey)
    )
    if (!payload) {
      throw new Error('远端设置为空')
    }
    this.updateCachedSettings(payload)
    this.markSummaryDirty()
    return payload
  }

  private async request(op: string, payloadJson?: string, expectedSessionKey?: string,
    timeoutMs: number = REMOTE_RPC_TIMEOUT_MS): Promise<string | undefined> {
    const runtime = this.clientRuntime
    if (!runtime || !runtime.connected) {
      throw new Error('远端未连接')
    }
    if (expectedSessionKey && `${runtime.sessionId}` !== expectedSessionKey) {
      throw new Error('远端连接已变化，请重新进入页面')
    }
    const id = `r${Date.now()}_${++this.requestSeq}`
    const request: RemoteRpcRequest = { id, op, payloadJson }
    const promise = new Promise<string | undefined>((resolve: (payloadJson: string | undefined) => void,
      reject: (error: Error) => void) => {
      const timer = setTimeout(() => {
        runtime.pending.delete(id)
        reject(new Error(`远端请求超时: ${op}`))
      }, timeoutMs)
      runtime.pending.set(id, {
        resolve,
        reject,
        timer
      })
    })
    try {
      await this.sendPacket(runtime, request)
    } catch (error) {
      const pending = runtime.pending.get(id)
      if (pending) {
        clearTimeout(pending.timer)
        runtime.pending.delete(id)
        pending.reject(new Error(safeErrorText(error as Object)))
      }
    }
    return promise
  }

  private stringifyPayload(payload: Object): string {
    return JSON.stringify(payload)
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
        return '系统内部错误，请检查对端是否安装 EasyTier、协同权限是否授权，以及系统协同能力是否可用'
      default:
        return `未知连接错误 ${result.errorCode ?? 'unknown'}`
    }
  }

  private updateCachedSettings(settings: RemoteSettingsState): void {
    if (this.lastSummary) {
      this.lastSummary.settings = settings
    }
  }

  private updateCachedConfigName(configId: string, displayName: string): void {
    if (!this.lastSummary) {
      return
    }
    const target = this.lastSummary.configs.find((item) => item.configId === configId)
    if (target) {
      target.displayName = displayName
    }
  }

  private removeCachedConfig(configId: string): void {
    if (!this.lastSummary) {
      return
    }
    this.lastSummary.configs = this.lastSummary.configs.filter((item) => item.configId !== configId)
    this.lastSummary.runtime.configCount = this.lastSummary.configs.length
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

  markSummaryDirty(): void {
    EventHelper.emitterPublish(REMOTE_MANAGE_SUMMARY_DIRTY_EVENT, {
      data: {
        sessionKey: this.currentSessionKey ?? ''
      }
    })
  }

  notifyHostSummaryDirty(): void {
    if (this.hostSummaryDirtyNotifyTimer >= 0) {
      return
    }
    this.hostSummaryDirtyNotifyTimer = setTimeout(() => {
      this.hostSummaryDirtyNotifyTimer = -1
      const notify: RemoteRpcNotify = { event: REMOTE_NOTIFY_SUMMARY_DIRTY }
      Array.from(this.hostRuntimes.values()).forEach((runtime) => {
        if (!runtime.connected) {
          return
        }
        this.sendPacket(runtime, notify).catch((error: Error) => {
          Logger.error(`[RemoteManageHost] send notify failed: ${error.message}`, 'RemoteManageService')
        })
      })
    }, 250)
  }

  private parseResponse<T>(payloadJson: string | undefined): T | undefined {
    if (!payloadJson || payloadJson.length === 0) {
      return undefined
    }
    try {
      return JSON.parse(payloadJson) as T
    } catch (_) {
      return undefined
    }
  }

  private parseRequestPayload<T>(request: RemoteRpcRequest): T | undefined {
    if (!request.payloadJson || request.payloadJson.length === 0) {
      return undefined
    }
    try {
      return JSON.parse(request.payloadJson) as T
    } catch (_) {
      return undefined
    }
  }

  private createRuntime(sessionId: number, role: 'client' | 'host', deviceName: string): RemoteSessionRuntime {
    const runtime: RemoteSessionRuntime = {
      sessionId,
      role,
      deviceName,
      connected: false,
      hostLifecycleActive: false,
      pending: new Map(),
      incoming: new Map(),
      connectCallback: (callbackInfo: abilityConnectionManager.EventCallbackInfo) => {
        runtime.connected = true
        Logger.info(`[RemoteManage] connect role=${role} session=${callbackInfo.sessionId}`, 'RemoteManageService')
      },
      disconnectCallback: (callbackInfo: abilityConnectionManager.EventCallbackInfo) => {
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
      },
      receiveMessageCallback: (callbackInfo: abilityConnectionManager.EventCallbackInfo) => {
        if (!callbackInfo.msg) {
          return
        }
        this.onRawMessage(runtime, callbackInfo.msg)
      }
    }
    return runtime
  }

  private registerSessionEvents(runtime: RemoteSessionRuntime): void {
    abilityConnectionManager.on('connect', runtime.sessionId, runtime.connectCallback)
    abilityConnectionManager.on('disconnect', runtime.sessionId, runtime.disconnectCallback)
    abilityConnectionManager.on('receiveMessage', runtime.sessionId, runtime.receiveMessageCallback)
  }

  private cleanupRuntime(runtime: RemoteSessionRuntime, destroy: boolean): void {
    this.notifyHostDisconnected(runtime)
    try {
      abilityConnectionManager.off('connect', runtime.sessionId, runtime.connectCallback)
    } catch (_) {
    }
    try {
      abilityConnectionManager.off('disconnect', runtime.sessionId, runtime.disconnectCallback)
    } catch (_) {
    }
    try {
      abilityConnectionManager.off('receiveMessage', runtime.sessionId, runtime.receiveMessageCallback)
    } catch (_) {
    }
    runtime.connected = false
    runtime.incoming.clear()
    runtime.pending.forEach((pending) => {
      clearTimeout(pending.timer)
      pending.reject(new Error('远端连接已断开'))
    })
    runtime.pending.clear()
    if (destroy) {
      try {
        abilityConnectionManager.destroyAbilityConnectionSession(runtime.sessionId)
      } catch (_) {
      }
    }
  }

  private notifyHostConnected(runtime: RemoteSessionRuntime): void {
    if (runtime.role !== 'host' || runtime.hostLifecycleActive) {
      return
    }
    runtime.hostLifecycleActive = true
    try {
      this.hostHandlerProvider?.().onRemoteManageConnected?.()
    } catch (error) {
      Logger.error(`[RemoteManageHost] notify connected failed: ${safeErrorText(error as Object)}`,
        'RemoteManageService')
    }
  }

  private notifyHostDisconnected(runtime: RemoteSessionRuntime): void {
    if (runtime.role !== 'host' || !runtime.hostLifecycleActive) {
      return
    }
    runtime.hostLifecycleActive = false
    try {
      this.hostHandlerProvider?.().onRemoteManageDisconnected?.()
    } catch (error) {
      Logger.error(`[RemoteManageHost] notify disconnected failed: ${safeErrorText(error as Object)}`,
        'RemoteManageService')
    }
  }

  private previousCodePointEnd(text: string, start: number, end: number): number {
    if (end <= start) {
      return start
    }
    let nextEnd = end - 1
    const code = text.charCodeAt(nextEnd)
    if (code >= 0xDC00 && code <= 0xDFFF && nextEnd > start) {
      nextEnd -= 1
    } else if (code >= 0xD800 && code <= 0xDBFF && end < text.length) {
      const next = text.charCodeAt(end)
      if (next >= 0xDC00 && next <= 0xDFFF) {
        nextEnd -= 1
      }
    }
    return Math.max(start, nextEnd)
  }

  private buildFrame(packetId: string, part: number, total: number, data: string): RemoteWireFrame {
    return {
      v: REMOTE_MANAGE_PROTOCOL_VERSION,
      service: REMOTE_MANAGE_SERVICE_NAME,
      packetId,
      part,
      total,
      data
    }
  }

  private takeFrameChunk(raw: string, offset: number, packetId: string, part: number): string {
    let end = Math.min(raw.length, offset + 256)
    if (end <= offset) {
      return ''
    }
    let chunk = raw.substring(offset, end)
    while (chunk.length > 0 &&
      utf8ByteLength(JSON.stringify(this.buildFrame(packetId, part, 999999, chunk))) > REMOTE_FRAME_MAX_BYTES) {
      end = this.previousCodePointEnd(raw, offset, end)
      chunk = raw.substring(offset, end)
    }
    if (chunk.length === 0) {
      throw new Error('远端消息分片失败')
    }
    return chunk
  }

  private splitPacket(raw: string, packetId: string): string[] {
    const chunks: string[] = []
    let offset = 0
    while (offset < raw.length) {
      const chunk = this.takeFrameChunk(raw, offset, packetId, chunks.length)
      chunks.push(chunk)
      if (chunks.length > REMOTE_MAX_PACKET_CHUNKS) {
        throw new Error('远端消息过大')
      }
      offset += chunk.length
    }
    if (chunks.length === 0) {
      chunks.push('')
    }
    return chunks
  }

  private async sendPacket(runtime: RemoteSessionRuntime,
    packet: RemoteRpcRequest | RemoteRpcResponse | RemoteRpcNotify): Promise<void> {
    const raw = JSON.stringify(packet)
    const packetId = `p${Date.now()}_${++this.packetSeq}`
    const chunks = this.splitPacket(raw, packetId)
    const total = chunks.length
    for (let part = 0; part < total; part++) {
      const frame: RemoteWireFrame = {
        v: REMOTE_MANAGE_PROTOCOL_VERSION,
        service: REMOTE_MANAGE_SERVICE_NAME,
        packetId,
        part,
        total,
        data: chunks[part]
      }
      const frameText = JSON.stringify(frame)
      if (utf8ByteLength(frameText) > REMOTE_SEND_MESSAGE_MAX_BYTES) {
        throw new Error('远端消息分片超过 1KB 限制')
      }
      await abilityConnectionManager.sendMessage(runtime.sessionId, frameText)
    }
  }

  private pruneIncomingPackets(runtime: RemoteSessionRuntime): void {
    const now = Date.now()
    runtime.incoming.forEach((packet, packetId) => {
      if (now - packet.createdAt > REMOTE_INCOMING_PACKET_TTL_MS) {
        runtime.incoming.delete(packetId)
      }
    })
    while (runtime.incoming.size > REMOTE_INCOMING_MAX_PACKETS) {
      const first = runtime.incoming.keys().next()
      if (first.done) {
        return
      }
      runtime.incoming.delete(first.value)
    }
  }

  private onRawMessage(runtime: RemoteSessionRuntime, rawMessage: string): void {
    let frame: RemoteWireFrame
    try {
      frame = JSON.parse(rawMessage) as RemoteWireFrame
    } catch (error) {
      Logger.error(`[RemoteManage] parse frame failed: ${safeErrorText(error as Object)}`, 'RemoteManageService')
      return
    }
    if (frame.service !== REMOTE_MANAGE_SERVICE_NAME || frame.v !== REMOTE_MANAGE_PROTOCOL_VERSION ||
      frame.total <= 0 || frame.total > REMOTE_MAX_PACKET_CHUNKS || frame.part < 0 || frame.part >= frame.total) {
      return
    }
    let packetText = ''
    if (frame.total === 1) {
      packetText = frame.data
    } else {
      this.pruneIncomingPackets(runtime)
      let incoming = runtime.incoming.get(frame.packetId)
      if (incoming && incoming.total !== frame.total) {
        runtime.incoming.delete(frame.packetId)
        return
      }
      if (!incoming) {
        if (runtime.incoming.size >= REMOTE_INCOMING_MAX_PACKETS) {
          this.pruneIncomingPackets(runtime)
        }
        incoming = {
          total: frame.total,
          chunks: new Array<string>(frame.total),
          received: 0,
          createdAt: Date.now()
        }
        runtime.incoming.set(frame.packetId, incoming)
      }
      if (incoming.chunks[frame.part] === undefined) {
        incoming.chunks[frame.part] = frame.data
        incoming.received += 1
      }
      if (incoming.received < incoming.total) {
        return
      }
      runtime.incoming.delete(frame.packetId)
      packetText = incoming.chunks.join('')
    }
    try {
      if (runtime.role === 'client') {
        const packet = JSON.parse(packetText) as RemoteRpcResponse | RemoteRpcNotify
        if ((packet as RemoteRpcNotify).event !== undefined) {
          this.onClientNotify(packet as RemoteRpcNotify)
        } else {
          this.onClientPacket(runtime, packet as RemoteRpcResponse)
        }
      } else {
        const request = JSON.parse(packetText) as RemoteRpcRequest
        this.onHostPacket(runtime, request)
      }
    } catch (error) {
      Logger.error(`[RemoteManage] parse packet failed: ${safeErrorText(error as Object)}`, 'RemoteManageService')
    }
  }

  private onClientNotify(notify: RemoteRpcNotify): void {
    if (notify.event === REMOTE_NOTIFY_SUMMARY_DIRTY) {
      this.markSummaryDirty()
    }
  }

  private onClientPacket(runtime: RemoteSessionRuntime, response: RemoteRpcResponse): void {
    const pending = runtime.pending.get(response.id)
    if (!pending) {
      return
    }
    clearTimeout(pending.timer)
    runtime.pending.delete(response.id)
    if (response.ok) {
      pending.resolve(response.payloadJson)
    } else {
      pending.reject(new Error(response.error ?? '远端请求失败'))
    }
  }

  private onHostPacket(runtime: RemoteSessionRuntime, request: RemoteRpcRequest): void {
    this.handleHostRequest(request).then((payloadJson) => {
      const response: RemoteRpcResponse = {
        id: request.id,
        ok: true,
        payloadJson
      }
      this.sendPacket(runtime, response).catch((error: Error) => {
        Logger.error(`[RemoteManageHost] send response failed: ${error.message}`, 'RemoteManageService')
      })
    }).catch((error: Error) => {
      const response: RemoteRpcResponse = {
        id: request.id,
        ok: false,
        error: error.message
      }
      this.sendPacket(runtime, response).catch(() => {
      })
    })
  }

  private async handleHostRequest(request: RemoteRpcRequest): Promise<string | undefined> {
    const provider = this.hostHandlerProvider
    if (!provider) {
      throw new Error('远端管理服务未初始化')
    }
    const handler = provider()
    await handler.waitReady()
    switch (request.op) {
      case 'summary':
      case 'hello':
        return this.stringifyPayload(handler.summary())
      case 'listConfigs': {
        const result: RemoteListConfigsResult = { configs: handler.listConfigs() }
        return this.stringifyPayload(result)
      }
      case 'getConfig': {
        const payload = this.parseRequestPayload<RemoteConfigIdPayload>(request)
        const result = payload ? handler.getConfig(payload.configId) : undefined
        return result ? this.stringifyPayload(result) : undefined
      }
      case 'getRuntimeInstance': {
        const payload = this.parseRequestPayload<RemoteConfigIdPayload>(request)
        const result = payload ? handler.getRuntimeInstance(payload.configId) : undefined
        return result ? this.stringifyPayload(result) : undefined
      }
      case 'getConfigFields': {
        const payload = this.parseRequestPayload<RemoteGetFieldsPayload>(request)
        return payload ? this.stringifyPayload(handler.getConfigFields(payload.configId, payload.fields)) : undefined
      }
      case 'setConfigField': {
        const payload = this.parseRequestPayload<RemoteSetConfigFieldPayload>(request)
        const result: RemoteBooleanResult = {
          ok: payload ? handler.setConfigField(payload.configId, payload.field, payload.value) : false
        }
        return this.stringifyPayload(result)
      }
      case 'saveConfig': {
        const payload = this.parseRequestPayload<RemoteSaveConfigPayload>(request)
        const result: RemoteBooleanResult = {
          ok: payload ? handler.saveConfig(payload.configId, payload.displayName, payload.config) : false
        }
        return this.stringifyPayload(result)
      }
      case 'createDefaultConfig': {
        const payload = this.parseRequestPayload<RemoteDisplayNamePayload>(request)
        const result = payload ? handler.createDefaultConfig(payload.displayName) : undefined
        return result ? this.stringifyPayload(result) : undefined
      }
      case 'importConfig': {
        const payload = this.parseRequestPayload<RemoteImportConfigPayload>(request)
        const result = payload ? handler.importConfig(payload.config, payload.displayName) : undefined
        return result ? this.stringifyPayload(result) : undefined
      }
      case 'deleteConfig': {
        const payload = this.parseRequestPayload<RemoteConfigIdPayload>(request)
        const result: RemoteBooleanResult = { ok: payload ? handler.deleteConfig(payload.configId) : false }
        return this.stringifyPayload(result)
      }
      case 'renameConfig': {
        const payload = this.parseRequestPayload<RemoteRenameConfigPayload>(request)
        const result: RemoteBooleanResult = {
          ok: payload ? handler.renameConfig(payload.configId, payload.displayName) : false
        }
        return this.stringifyPayload(result)
      }
      case 'startConfig': {
        const payload = this.parseRequestPayload<RemoteConfigIdPayload>(request)
        const ok = payload ? handler.startConfig(payload.configId) : false
        const result: RemoteActionSummaryResult = { ok, summary: handler.summary() }
        return this.stringifyPayload(result)
      }
      case 'stopConfig': {
        const payload = this.parseRequestPayload<RemoteConfigIdPayload>(request)
        const ok = payload ? handler.stopConfig(payload.configId) : false
        const result: RemoteActionSummaryResult = { ok, summary: handler.summary() }
        return this.stringifyPayload(result)
      }
      case 'exportToml': {
        const payload = this.parseRequestPayload<RemoteConfigIdPayload>(request)
        const result: RemoteExportTomlResult = { toml: payload ? handler.exportToml(payload.configId) ?? '' : '' }
        return this.stringifyPayload(result)
      }
      case 'getSettings':
        return this.stringifyPayload(handler.getSettings())
      case 'setSetting': {
        const payload = this.parseRequestPayload<RemoteSetSettingPayload>(request)
        const value: boolean | string = payload?.valueString !== undefined ? payload.valueString : payload?.valueBoolean ?? false
        return payload ? this.stringifyPayload(handler.setSetting(payload.key, value)) : undefined
      }
      case 'requestPermission': {
        const payload = this.parseRequestPayload<RemotePermissionPayload>(request)
        const settings = await handler.requestPermission(payload?.kind ?? '')
        return this.stringifyPayload(settings)
      }
      default:
        throw new Error(`未知远端请求: ${request.op}`)
    }
  }
}

export const RemoteManageService = new RemoteManageServiceClass()
