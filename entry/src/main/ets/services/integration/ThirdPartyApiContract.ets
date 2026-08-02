import { Want } from '@kit.AbilityKit'
import { JSON } from '@kit.ArkTS'

export const THIRD_PARTY_API_SCHEMA_VERSION = 2
export const THIRD_PARTY_API_REQUEST_ACTION = 'top.frankhan.easytier.action.START_INSTANCE_REQUEST'
export const THIRD_PARTY_API_RESULT_ACTION = 'top.frankhan.easytier.action.START_INSTANCE_RESULT'
export const THIRD_PARTY_API_REQUEST_ID_KEY = 'top.frankhan.easytier.api.requestId'
export const THIRD_PARTY_API_OPERATION_KEY = 'top.frankhan.easytier.api.operation'
export const THIRD_PARTY_API_CALLER_BUNDLE_KEY = 'ohos.aafwk.param.callerBundleName'
export const THIRD_PARTY_API_CALLER_IDENTIFIER_KEY = 'ohos.aafwk.param.callerAppIdentifier'
export const EASYTIER_BUNDLE_NAME = 'top.frankhan.easytier'
export const EASYTIER_MODULE_NAME = 'entry'
export const EASYTIER_ABILITY_NAME = 'EntryAbility'
export const EASYTIER_APP_IDENTIFIER = '6917581172490635834'

export const THIRD_PARTY_OPERATION_START_INSTANCE = 'start_instance'

export const THIRD_PARTY_STATE_STOPPED = 'stopped'
export const THIRD_PARTY_STATE_STARTING = 'starting'
export const THIRD_PARTY_STATE_RUNNING = 'running'

export const THIRD_PARTY_RESULT_OK = 'OK'
export const THIRD_PARTY_RESULT_INVALID_REQUEST = 'INVALID_REQUEST'
export const THIRD_PARTY_RESULT_REQUEST_EXPIRED = 'REQUEST_EXPIRED'
export const THIRD_PARTY_RESULT_REPLAYED_REQUEST = 'REPLAYED_REQUEST'
export const THIRD_PARTY_RESULT_BUSY = 'BUSY'
export const THIRD_PARTY_RESULT_INSTANCE_NOT_FOUND = 'INSTANCE_NOT_FOUND'
export const THIRD_PARTY_RESULT_START_REJECTED = 'START_REJECTED'
export const THIRD_PARTY_RESULT_RUNTIME_TIMEOUT = 'RUNTIME_TIMEOUT'
export const THIRD_PARTY_RESULT_SNAPSHOT_PUBLISH_FAILED = 'SNAPSHOT_PUBLISH_FAILED'
export const THIRD_PARTY_RESULT_INTERNAL_ERROR = 'INTERNAL_ERROR'

export const THIRD_PARTY_REQUEST_TTL_MS = 5 * 60 * 1000
export const THIRD_PARTY_SNAPSHOT_TTL_MS = 15 * 1000
export const THIRD_PARTY_SNAPSHOT_HEARTBEAT_MS = 5 * 1000
export const THIRD_PARTY_SNAPSHOT_POLL_INTERVAL_MS = 500
export const THIRD_PARTY_FUTURE_CLOCK_SKEW_MS = 5000
export const THIRD_PARTY_MAX_SHARED_VALUE_LENGTH = 4096
export const THIRD_PARTY_MAX_INSTANCE_ID_LENGTH = 128
export const THIRD_PARTY_MAX_INSTANCE_NAME_LENGTH = 64
export const THIRD_PARTY_MAX_LIST_INSTANCES = 10

export class ThirdPartyApiPartner {
  bundleName: string
  appIdentifier: string
  requestUri: string
  capabilityUri: string
  snapshotUri: string
  resultUri: string
  callbackModuleName: string
  callbackAbilityName: string

  constructor(bundleName: string, appIdentifier: string, requestUri: string, capabilityUri: string,
    snapshotUri: string, resultUri: string, callbackModuleName: string, callbackAbilityName: string) {
    this.bundleName = bundleName
    this.appIdentifier = appIdentifier
    this.requestUri = requestUri
    this.capabilityUri = capabilityUri
    this.snapshotUri = snapshotUri
    this.resultUri = resultUri
    this.callbackModuleName = callbackModuleName
    this.callbackAbilityName = callbackAbilityName
  }
}

export const RUSTDESK_PARTNER = new ThirdPartyApiPartner(
  'top.frankhan.resk',
  '6917605780518421882',
  'datashareproxy://top.frankhan.resk/easytier_api/v2/start_request',
  'datashareproxy://top.frankhan.easytier/third_party_api/v2/capabilities/rustdesk',
  'datashareproxy://top.frankhan.easytier/third_party_api/v2/instance_snapshot/rustdesk',
  'datashareproxy://top.frankhan.easytier/third_party_api/v2/start_result/rustdesk',
  'entry',
  'EntryAbility'
)

const TRUSTED_PARTNERS: ThirdPartyApiPartner[] = [RUSTDESK_PARTNER]

export interface ThirdPartyApiRequestPayload {
  schemaVersion?: number
  requestId?: string
  operation?: string
  issuedAt?: number
  instanceId?: string
}

export interface ThirdPartyApiInstanceSummary {
  instanceId: string
  instanceName: string
  state: string
  virtualIpv4?: string
  peerCount: number
}

export interface ThirdPartyApiSnapshotPayload {
  schemaVersion: number
  updatedAt: number
  ttlMs: number
  instances: ThirdPartyApiInstanceSummary[]
  truncated: boolean
}

export interface ThirdPartyApiResultPayload {
  schemaVersion: number
  requestId: string
  operation: string
  issuedAt: number
  ok: boolean
  code: string
  message: string
  instance?: ThirdPartyApiInstanceSummary
}

export class ThirdPartyApiValidationResult {
  ok: boolean
  code: string
  message: string

  constructor(ok: boolean, code: string = THIRD_PARTY_RESULT_OK, message: string = '') {
    this.ok = ok
    this.code = code
    this.message = message
  }
}

export class ThirdPartyApiValidator {
  static isRequestWant(want: Want): boolean {
    return want.action === THIRD_PARTY_API_REQUEST_ACTION
  }

  static wantStringParameter(want: Want, key: string): string {
    const value = want.parameters?.[key]
    return typeof value === 'string' ? value : ''
  }

  static trustedPartner(want: Want): ThirdPartyApiPartner | undefined {
    const callerBundle = ThirdPartyApiValidator.wantStringParameter(want, THIRD_PARTY_API_CALLER_BUNDLE_KEY)
    const callerIdentifier = ThirdPartyApiValidator.wantStringParameter(
      want,
      THIRD_PARTY_API_CALLER_IDENTIFIER_KEY
    )
    return TRUSTED_PARTNERS.find((partner: ThirdPartyApiPartner) => {
      return partner.bundleName === callerBundle && partner.appIdentifier === callerIdentifier
    })
  }

  static parseRequest(value: string): ThirdPartyApiRequestPayload | undefined {
    try {
      const payload = JSON.parse(value) as ThirdPartyApiRequestPayload
      if (payload === null || typeof payload !== 'object' || Array.isArray(payload)) {
        return undefined
      }
      return payload
    } catch (_) {
      return undefined
    }
  }

  static parseSnapshot(value: string): ThirdPartyApiSnapshotPayload | undefined {
    try {
      const payload = JSON.parse(value) as ThirdPartyApiSnapshotPayload
      if (payload === null || typeof payload !== 'object' || Array.isArray(payload)) {
        return undefined
      }
      return payload
    } catch (_) {
      return undefined
    }
  }

  static isSnapshotFresh(payload: ThirdPartyApiSnapshotPayload, now: number): boolean {
    if (payload.schemaVersion !== THIRD_PARTY_API_SCHEMA_VERSION
      || !Number.isSafeInteger(payload.updatedAt) || payload.updatedAt <= 0
      || payload.ttlMs !== THIRD_PARTY_SNAPSHOT_TTL_MS
      || payload.updatedAt - now > THIRD_PARTY_FUTURE_CLOCK_SKEW_MS
      || now - payload.updatedAt > payload.ttlMs
      || !Array.isArray(payload.instances)) {
      return false
    }
    return true
  }

  static validateRequest(payload: ThirdPartyApiRequestPayload, expectedRequestId: string,
    now: number): ThirdPartyApiValidationResult {
    if (payload.schemaVersion !== THIRD_PARTY_API_SCHEMA_VERSION) {
      return new ThirdPartyApiValidationResult(false, THIRD_PARTY_RESULT_INVALID_REQUEST,
        '不支持的 EasyTier 三方 API 协议版本')
    }
    if (!ThirdPartyApiValidator.isRequestId(expectedRequestId) || payload.requestId !== expectedRequestId) {
      return new ThirdPartyApiValidationResult(false, THIRD_PARTY_RESULT_INVALID_REQUEST,
        '请求 ID 无效或与 Want 不一致')
    }
    if (!ThirdPartyApiValidator.isOperation(payload.operation)) {
      return new ThirdPartyApiValidationResult(false, THIRD_PARTY_RESULT_INVALID_REQUEST,
        '请求操作不受支持')
    }
    if (typeof payload.issuedAt !== 'number' || !Number.isSafeInteger(payload.issuedAt)
      || payload.issuedAt <= 0) {
      return new ThirdPartyApiValidationResult(false, THIRD_PARTY_RESULT_INVALID_REQUEST,
        '请求时间无效')
    }
    if (payload.issuedAt - now > THIRD_PARTY_FUTURE_CLOCK_SKEW_MS) {
      return new ThirdPartyApiValidationResult(false, THIRD_PARTY_RESULT_INVALID_REQUEST,
        '请求时间晚于本机时间')
    }
    if (now - payload.issuedAt > THIRD_PARTY_REQUEST_TTL_MS) {
      return new ThirdPartyApiValidationResult(false, THIRD_PARTY_RESULT_REQUEST_EXPIRED,
        '请求已超过 5 分钟，请重新发起')
    }
    if (!ThirdPartyApiValidator.isInstanceId(payload.instanceId)) {
      return new ThirdPartyApiValidationResult(false, THIRD_PARTY_RESULT_INVALID_REQUEST,
        '实例 ID 无效')
    }
    return new ThirdPartyApiValidationResult(true)
  }

  static isOperation(value: string | undefined): boolean {
    return value === THIRD_PARTY_OPERATION_START_INSTANCE
  }

  static isRequestId(value: string): boolean {
    return /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/.test(value)
  }

  static isInstanceId(value: string | undefined): boolean {
    if (!value || value !== value.trim() || value.length === 0
      || value.length > THIRD_PARTY_MAX_INSTANCE_ID_LENGTH) {
      return false
    }
    return /^[A-Za-z0-9._:-]+$/.test(value)
  }

  static safeInstanceName(value: string): string {
    const normalized = value.trim().replace(/[\u0000-\u001f\u007f]/g, '')
    return normalized.substring(0, THIRD_PARTY_MAX_INSTANCE_NAME_LENGTH)
  }
}
