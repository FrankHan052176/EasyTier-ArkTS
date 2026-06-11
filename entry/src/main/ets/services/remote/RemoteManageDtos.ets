import { ConfigFieldValue, ConfigJson } from '../../config/schema/SchemaConfig'
import { RuntimeMyNodeInfo } from '../../types/runtime/RuntimeTypes'

export interface RemoteDeviceLite {
  deviceId: string
  networkId?: string
  deviceName: string
}

export interface RemoteConfigMeta {
  configId: string
  displayName: string
  favorite?: boolean
  running?: boolean
}

export interface RemoteFieldValueResult {
  field: string
  rawValue?: string
  found: boolean
}

export interface RemoteRuntimeInstanceLite {
  configId: string
  instanceId: string
  displayName: string
  running: boolean
  myNodeInfo?: RuntimeMyNodeInfo
  peerCount: number
  routeCount: number
}

export interface RemoteRuntimeSummary {
  configCount: number
  runningCount: number
  runningConfigs: RemoteRuntimeInstanceLite[]
  runtimeDurationText: string
  memoryUsageText: string
}

export interface RemoteSettingsState {
  ext_mode: boolean
  dev: boolean
  vpn_routes: boolean
  force_global: boolean
  dns: string
  core_log: boolean
  debug_log: boolean
  distributePerm: boolean
}

export interface RemoteSummary {
  appVersion?: string
  coreVersion?: string
  deviceName?: string
  sdkApiVersion?: number
  configs: RemoteConfigMeta[]
  runtime: RemoteRuntimeSummary
  settings: RemoteSettingsState
}

export interface RemoteCreateDefaultConfigResult {
  configId: string
  displayName: string
  config: ConfigJson
}

export interface RemoteGetConfigResult {
  configId: string
  displayName: string
  config: ConfigJson
}

export interface RemoteGetFieldsResult {
  values: RemoteFieldValueResult[]
}

export interface RemoteListConfigsResult {
  configs: RemoteConfigMeta[]
}

export interface RemoteConfigIdPayload {
  configId: string
}

export interface RemoteGetFieldsPayload {
  configId: string
  fields: string[]
}

export interface RemoteSetConfigFieldPayload {
  configId: string
  field: string
  value: ConfigFieldValue
}

export interface RemoteSaveConfigPayload {
  configId: string
  displayName: string
  config: ConfigJson
}

export interface RemoteDisplayNamePayload {
  displayName: string
}

export interface RemoteImportConfigPayload {
  displayName: string
  config: ConfigJson
}

export interface RemoteRenameConfigPayload {
  configId: string
  displayName: string
}

export interface RemoteBooleanResult {
  ok: boolean
}

export interface RemoteActionSummaryResult {
  ok: boolean
  summary?: RemoteSummary
}

export interface RemoteExportTomlResult {
  toml: string
}

export interface RemoteSetSettingPayload {
  key: string
  valueBoolean?: boolean
  valueString?: string
}

export interface RemotePermissionPayload {
  kind: string
}
