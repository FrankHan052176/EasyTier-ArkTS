import { common, Want } from '@kit.AbilityKit'
import { dataShare, preferences } from '@kit.ArkData'
import { JSON } from '@kit.ArkTS'
import { BusinessError } from '@kit.BasicServicesKit'
import { AppManager } from '../../AppManager'
import { Logger } from '../../shared/logging/Logger'
import {
  THIRD_PARTY_API_REQUEST_ID_KEY,
  THIRD_PARTY_API_RESULT_ACTION,
  THIRD_PARTY_API_SCHEMA_VERSION,
  THIRD_PARTY_MAX_LIST_INSTANCES,
  THIRD_PARTY_MAX_SHARED_VALUE_LENGTH,
  THIRD_PARTY_RESULT_BUSY,
  THIRD_PARTY_RESULT_INSTANCE_NOT_FOUND,
  THIRD_PARTY_RESULT_INTERNAL_ERROR,
  THIRD_PARTY_RESULT_INVALID_REQUEST,
  THIRD_PARTY_RESULT_OK,
  THIRD_PARTY_RESULT_REPLAYED_REQUEST,
  THIRD_PARTY_RESULT_RUNTIME_TIMEOUT,
  THIRD_PARTY_RESULT_SNAPSHOT_PUBLISH_FAILED,
  THIRD_PARTY_RESULT_START_REJECTED,
  THIRD_PARTY_SNAPSHOT_HEARTBEAT_MS,
  THIRD_PARTY_SNAPSHOT_POLL_INTERVAL_MS,
  THIRD_PARTY_SNAPSHOT_TTL_MS,
  THIRD_PARTY_STATE_RUNNING,
  THIRD_PARTY_STATE_STARTING,
  THIRD_PARTY_STATE_STOPPED,
  RUSTDESK_PARTNER,
  ThirdPartyApiInstanceSummary,
  ThirdPartyApiPartner,
  ThirdPartyApiRequestPayload,
  ThirdPartyApiResultPayload,
  ThirdPartyApiSnapshotPayload,
  ThirdPartyApiValidationResult,
  ThirdPartyApiValidator
} from './ThirdPartyApiContract'

const TAG = 'ThirdPartyApiService'
const REPLAY_PREFERENCES_NAME = 'easytier_third_party_api'
const CONSUMED_REQUEST_IDS_KEY = 'consumed_request_ids'
const MAX_REMEMBERED_REQUESTS = 64
const START_ACCEPT_TIMEOUT_MS = 90 * 1000
const RUNTIME_READY_TIMEOUT_MS = 30 * 1000
const POLL_INTERVAL_MS = 100

class AsyncBooleanOutcome {
  completed: boolean = false
  value: boolean = false
  errorMessage: string = ''
}

export class ThirdPartyApiService {
  private readonly context: common.UIAbilityContext
  private activePartners: Set<string> = new Set<string>()
  private consumedRequestIds: Set<string> = new Set<string>()
  private snapshotTimer: number | undefined = undefined
  private snapshotSignature: string = ''
  private snapshotPublishedAt: number = 0
  private snapshotPublishing: boolean = false
  private destroyed: boolean = false

  constructor(context: common.UIAbilityContext) {
    this.context = context
  }

  static isRequestWant(want: Want): boolean {
    return ThirdPartyApiValidator.isRequestWant(want)
  }

  start(): void {
    if (this.destroyed || this.snapshotTimer !== undefined) {
      return
    }
    void this.refreshSnapshot(true)
    this.snapshotTimer = setInterval(() => {
      void this.refreshSnapshot(false)
    }, THIRD_PARTY_SNAPSHOT_POLL_INTERVAL_MS)
  }

  destroy(): void {
    this.destroyed = true
    if (this.snapshotTimer !== undefined) {
      clearInterval(this.snapshotTimer)
      this.snapshotTimer = undefined
    }
    this.activePartners.clear()
  }

  async handleWant(want: Want): Promise<void> {
    if (this.destroyed || !ThirdPartyApiValidator.isRequestWant(want)) {
      return
    }
    const partner = ThirdPartyApiValidator.trustedPartner(want)
    if (!partner) {
      Logger.warn('拒绝未登记调用方的三方 API 请求', TAG)
      return
    }
    const requestId = ThirdPartyApiValidator.wantStringParameter(want, THIRD_PARTY_API_REQUEST_ID_KEY)
    if (want.uri !== partner.requestUri) {
      await this.publishAndReturn(partner, this.errorResult(
        requestId,
        '',
        THIRD_PARTY_RESULT_INVALID_REQUEST,
        '请求共享配置 URI 与登记调用方不匹配'
      ))
      return
    }
    if (this.activePartners.has(partner.appIdentifier)) {
      await this.publishAndReturn(partner, this.errorResult(
        requestId,
        '',
        THIRD_PARTY_RESULT_BUSY,
        '该调用方已有 EasyTier 请求正在处理'
      ))
      return
    }

    this.activePartners.add(partner.appIdentifier)
    try {
      const request = await this.readRequest(partner)
      const validation = ThirdPartyApiValidator.validateRequest(request, requestId, Date.now())
      if (!validation.ok) {
        await this.publishAndReturn(partner, this.validationErrorResult(requestId, request, validation))
        return
      }
      if (this.isConsumed(requestId) || !this.rememberConsumed(requestId)) {
        await this.publishAndReturn(partner, this.errorResult(
          requestId,
          request.operation ?? '',
          THIRD_PARTY_RESULT_REPLAYED_REQUEST,
          '该请求已经处理，请使用新的请求 ID'
        ))
        return
      }
      const result = await this.execute(request)
      await this.publishAndReturn(partner, result)
    } catch (error) {
      const message = ThirdPartyApiService.errorMessage(error as Object)
      Logger.error(`三方 API 请求失败：${message}`, TAG)
      await this.publishAndReturn(partner, this.errorResult(
        requestId,
        '',
        THIRD_PARTY_RESULT_INTERNAL_ERROR,
        message
      ))
    } finally {
      this.activePartners.delete(partner.appIdentifier)
    }
  }

  private async readRequest(partner: ThirdPartyApiPartner): Promise<ThirdPartyApiRequestPayload> {
    const handle = await dataShare.createDataProxyHandle()
    const config: dataShare.DataProxyConfig = {
      type: dataShare.DataProxyType.SHARED_CONFIG
    }
    const results = await handle.get([partner.requestUri], config)
    if (results.length !== 1 || results[0].uri !== partner.requestUri) {
      throw new Error('未找到调用方发布的 EasyTier 请求')
    }
    const result = results[0]
    if (result.result === dataShare.DataProxyErrorCode.NO_PERMISSION) {
      throw new Error('调用方未将 EasyTier appIdentifier 加入共享配置 allowList')
    }
    if (result.result !== dataShare.DataProxyErrorCode.SUCCESS) {
      throw new Error(`读取调用方共享配置失败（${result.result}）`)
    }
    if (typeof result.value !== 'string' || result.value.length === 0
      || result.value.length > THIRD_PARTY_MAX_SHARED_VALUE_LENGTH) {
      throw new Error('调用方共享配置内容为空或超过 4096 字节')
    }
    const request = ThirdPartyApiValidator.parseRequest(result.value)
    if (!request) {
      throw new Error('调用方共享配置不是有效的请求 JSON')
    }
    return request
  }

  private async execute(request: ThirdPartyApiRequestPayload): Promise<ThirdPartyApiResultPayload> {
    const requestId = request.requestId ?? ''
    const operation = request.operation ?? ''
    const instanceId = request.instanceId ?? ''
    if (!AppManager.easytier.getConfig(instanceId)) {
      return this.errorResult(
        requestId,
        operation,
        THIRD_PARTY_RESULT_INSTANCE_NOT_FOUND,
        '指定的 EasyTier 实例不存在'
      )
    }
    return await this.startInstance(requestId, instanceId, operation)
  }

  private instanceResult(requestId: string, operation: string, instanceId: string,
    message: string): ThirdPartyApiResultPayload {
    const name = AppManager.easytier.getConfigName(instanceId) ?? instanceId
    const result: ThirdPartyApiResultPayload = {
      schemaVersion: THIRD_PARTY_API_SCHEMA_VERSION,
      requestId,
      operation,
      issuedAt: Date.now(),
      ok: true,
      code: THIRD_PARTY_RESULT_OK,
      message,
      instance: this.instanceSummary(instanceId, name)
    }
    return result
  }

  private async startInstance(requestId: string, instanceId: string,
    operation: string): Promise<ThirdPartyApiResultPayload> {
    if (AppManager.easytier.getConfirmedRunningInstance(instanceId)) {
      if (!await this.refreshSnapshot(true)) {
        return this.errorResult(
          requestId,
          operation,
          THIRD_PARTY_RESULT_SNAPSHOT_PUBLISH_FAILED,
          '实例已运行，但实时快照发布失败'
        )
      }
      return this.instanceResult(
        requestId,
        operation,
        instanceId,
        'EasyTier 实例已在运行'
      )
    }

    if (!AppManager.easytier.isRuntimeStarting(instanceId)) {
      const startOutcome = await this.waitBoolean(
        AppManager.easytier.startAfterStop(instanceId),
        START_ACCEPT_TIMEOUT_MS
      )
      if (!startOutcome.completed) {
        return this.errorResult(
          requestId,
          operation,
          THIRD_PARTY_RESULT_RUNTIME_TIMEOUT,
          '等待 EasyTier 启动或系统 VPN 授权超时'
        )
      }
      if (startOutcome.errorMessage.length > 0 || !startOutcome.value) {
        return this.errorResult(
          requestId,
          operation,
          THIRD_PARTY_RESULT_START_REJECTED,
          startOutcome.errorMessage.length > 0 ? startOutcome.errorMessage : 'EasyTier 未接受实例启动请求'
        )
      }
    }

    if (!await this.waitRuntimeReady(instanceId, RUNTIME_READY_TIMEOUT_MS)) {
      return this.errorResult(
        requestId,
        operation,
        THIRD_PARTY_RESULT_RUNTIME_TIMEOUT,
        'EasyTier 内核未在限定时间内确认实例运行'
      )
    }
    if (!await this.refreshSnapshot(true)) {
      return this.errorResult(
        requestId,
        operation,
        THIRD_PARTY_RESULT_SNAPSHOT_PUBLISH_FAILED,
        '实例已运行，但实时快照发布失败'
      )
    }
    return this.instanceResult(
      requestId,
      operation,
      instanceId,
      'EasyTier 实例已启动并由内核确认运行'
    )
  }

  private instanceSummary(instanceId: string, instanceName: string): ThirdPartyApiInstanceSummary {
    const confirmed = AppManager.easytier.getConfirmedRunningInstance(instanceId)
    const observed = AppManager.easytier.getRunningInstance(instanceId)
    let state = THIRD_PARTY_STATE_STOPPED
    if (confirmed) {
      state = THIRD_PARTY_STATE_RUNNING
    } else if (observed || AppManager.easytier.isRuntimeStarting(instanceId)) {
      state = THIRD_PARTY_STATE_STARTING
    }
    const summary: ThirdPartyApiInstanceSummary = {
      instanceId,
      instanceName: ThirdPartyApiValidator.safeInstanceName(instanceName),
      state,
      peerCount: confirmed?.peers.length ?? 0
    }
    if (confirmed) {
      const virtualIpv4 = confirmed.myNodeInfo?.virtualIpv4
      if (virtualIpv4 && virtualIpv4.length > 0) {
        summary.virtualIpv4 = virtualIpv4
      }
    }
    return summary
  }

  private buildSnapshot(updatedAt: number): ThirdPartyApiSnapshotPayload {
    const stored = AppManager.easytier.listStoredConfigs()
    stored.sort((left, right) => left.configId.localeCompare(right.configId))
    const instances: ThirdPartyApiInstanceSummary[] = []
    const count = Math.min(stored.length, THIRD_PARTY_MAX_LIST_INSTANCES)
    for (let index = 0; index < count; index += 1) {
      const config = stored[index]
      instances.push(this.instanceSummary(config.configId, config.displayName))
    }
    const snapshot: ThirdPartyApiSnapshotPayload = {
      schemaVersion: THIRD_PARTY_API_SCHEMA_VERSION,
      updatedAt,
      ttlMs: THIRD_PARTY_SNAPSHOT_TTL_MS,
      instances,
      truncated: stored.length > count
    }
    return snapshot
  }

  private async refreshSnapshot(force: boolean): Promise<boolean> {
    if (this.destroyed) {
      return false
    }
    if (this.snapshotPublishing) {
      if (!force) {
        return true
      }
      const waitStartedAt = Date.now()
      while (this.snapshotPublishing && !this.destroyed && Date.now() - waitStartedAt < 2000) {
        await this.delay(25)
      }
      if (this.snapshotPublishing || this.destroyed) {
        return false
      }
    }

    const now = Date.now()
    const snapshot = this.buildSnapshot(0)
    const signature = JSON.stringify(snapshot)
    const heartbeatDue = now - this.snapshotPublishedAt >= THIRD_PARTY_SNAPSHOT_HEARTBEAT_MS
    if (!force && signature === this.snapshotSignature && !heartbeatDue) {
      return true
    }
    snapshot.updatedAt = now
    const value = JSON.stringify(snapshot)
    if (value.length === 0 || value.length > THIRD_PARTY_MAX_SHARED_VALUE_LENGTH) {
      Logger.error('实例快照超过共享配置大小限制', TAG)
      return false
    }

    this.snapshotPublishing = true
    try {
      const handle = await dataShare.createDataProxyHandle()
      const config: dataShare.DataProxyConfig = {
        type: dataShare.DataProxyType.SHARED_CONFIG
      }
      const proxyData: dataShare.ProxyData[] = [{
        uri: RUSTDESK_PARTNER.snapshotUri,
        value,
        allowList: [RUSTDESK_PARTNER.appIdentifier]
      }]
      const results = await handle.publish(proxyData, config)
      if (results.length !== 1 || results[0].uri !== RUSTDESK_PARTNER.snapshotUri
        || results[0].result !== dataShare.DataProxyErrorCode.SUCCESS) {
        Logger.error('系统拒绝发布实例快照', TAG)
        return false
      }
      this.snapshotSignature = signature
      this.snapshotPublishedAt = now
      return true
    } catch (error) {
      Logger.error(`发布实例快照失败：${ThirdPartyApiService.errorMessage(error as Object)}`, TAG)
      return false
    } finally {
      this.snapshotPublishing = false
    }
  }

  private async waitBoolean(operation: Promise<boolean>, timeoutMs: number): Promise<AsyncBooleanOutcome> {
    const outcome = new AsyncBooleanOutcome()
    operation.then((value: boolean) => {
      outcome.value = value
      outcome.completed = true
    }).catch((error: Error) => {
      outcome.errorMessage = error.message
      outcome.completed = true
    })
    const startedAt = Date.now()
    while (!outcome.completed && !this.destroyed && Date.now() - startedAt < timeoutMs) {
      await this.delay(POLL_INTERVAL_MS)
    }
    return outcome
  }

  private async waitRuntimeReady(instanceId: string, timeoutMs: number): Promise<boolean> {
    const startedAt = Date.now()
    while (!this.destroyed && Date.now() - startedAt < timeoutMs) {
      if (AppManager.easytier.getConfirmedRunningInstance(instanceId)) {
        return true
      }
      await this.delay(POLL_INTERVAL_MS)
    }
    return false
  }

  private delay(delayMs: number): Promise<void> {
    return new Promise<void>((resolve) => {
      setTimeout(resolve, delayMs)
    })
  }

  private validationErrorResult(requestId: string, request: ThirdPartyApiRequestPayload,
    validation: ThirdPartyApiValidationResult): ThirdPartyApiResultPayload {
    return this.errorResult(requestId, request.operation ?? '', validation.code, validation.message)
  }

  private errorResult(requestId: string, operation: string, code: string,
    message: string): ThirdPartyApiResultPayload {
    const result: ThirdPartyApiResultPayload = {
      schemaVersion: THIRD_PARTY_API_SCHEMA_VERSION,
      requestId,
      operation,
      issuedAt: Date.now(),
      ok: false,
      code,
      message
    }
    return result
  }

  private async publishAndReturn(partner: ThirdPartyApiPartner, result: ThirdPartyApiResultPayload): Promise<void> {
    if (this.destroyed) {
      return
    }
    const value = JSON.stringify(result)
    if (value.length === 0 || value.length > THIRD_PARTY_MAX_SHARED_VALUE_LENGTH) {
      Logger.error('三方 API 结果超过共享配置大小限制', TAG)
      return
    }
    try {
      const handle = await dataShare.createDataProxyHandle()
      const config: dataShare.DataProxyConfig = {
        type: dataShare.DataProxyType.SHARED_CONFIG
      }
      const proxyData: dataShare.ProxyData[] = [{
        uri: partner.resultUri,
        value,
        allowList: [partner.appIdentifier]
      }]
      const publishResults = await handle.publish(proxyData, config)
      if (publishResults.length !== 1 || publishResults[0].uri !== partner.resultUri
        || publishResults[0].result !== dataShare.DataProxyErrorCode.SUCCESS) {
        Logger.error('系统拒绝发布三方 API 结果', TAG)
        return
      }
    } catch (error) {
      Logger.error(`发布三方 API 结果失败：${ThirdPartyApiService.errorMessage(error as Object)}`, TAG)
      return
    }

    const callbackWant: Want = {
      bundleName: partner.bundleName,
      moduleName: partner.callbackModuleName,
      abilityName: partner.callbackAbilityName,
      action: THIRD_PARTY_API_RESULT_ACTION,
      uri: partner.resultUri,
      parameters: {
        'top.frankhan.easytier.api.requestId': result.requestId,
        'top.frankhan.easytier.api.operation': result.operation
      }
    }
    try {
      await this.context.startAbility(callbackWant)
    } catch (error) {
      Logger.error(`三方 API 结果已发布，但无法拉回调用方：${ThirdPartyApiService.errorMessage(error as Object)}`, TAG)
    }
  }

  private isConsumed(requestId: string): boolean {
    this.loadConsumedRequestIds().forEach((storedId: string) => {
      this.consumedRequestIds.add(storedId)
    })
    return this.consumedRequestIds.has(requestId)
  }

  private rememberConsumed(requestId: string): boolean {
    if (!ThirdPartyApiValidator.isRequestId(requestId) || this.consumedRequestIds.has(requestId)) {
      return false
    }
    try {
      const store = preferences.getPreferencesSync(this.context, { name: REPLAY_PREFERENCES_NAME })
      const ids = this.loadConsumedRequestIds(store)
      if (ids.indexOf(requestId) >= 0) {
        this.consumedRequestIds.add(requestId)
        return false
      }
      ids.push(requestId)
      while (ids.length > MAX_REMEMBERED_REQUESTS) {
        ids.shift()
      }
      store.putSync(CONSUMED_REQUEST_IDS_KEY, ids.join('\n'))
      store.flushSync()
      this.consumedRequestIds.add(requestId)
      return true
    } catch (error) {
      Logger.error(`保存三方 API 防重放状态失败：${ThirdPartyApiService.errorMessage(error as Object)}`, TAG)
      return false
    }
  }

  private loadConsumedRequestIds(store?: preferences.Preferences): string[] {
    try {
      const replayStore = store ?? preferences.getPreferencesSync(this.context, { name: REPLAY_PREFERENCES_NAME })
      const value = replayStore.getSync(CONSUMED_REQUEST_IDS_KEY, '') as string
      if (value.length === 0) {
        return []
      }
      return value.split('\n').filter((requestId: string, index: number, values: string[]) => {
        return ThirdPartyApiValidator.isRequestId(requestId) && values.indexOf(requestId) === index
      })
    } catch (_) {
      return []
    }
  }

  private static errorMessage(error: Object): string {
    const businessError = error as BusinessError
    if (typeof businessError.message === 'string' && businessError.message.trim().length > 0) {
      return businessError.message.trim()
    }
    const fallback = `${error}`.trim()
    return fallback.length > 0 ? fallback : 'EasyTier 三方 API 内部错误'
  }
}
