import { ConfigFieldValue, ConfigJson } from '../../config/schema/SchemaConfig'
import { RuntimeInstanceState, RuntimeMyNodeInfo } from '../../types/runtime/RuntimeTypes'

export const REMOTE_MANAGE_SERVICE_NAME = 'easytier.remote.manage.v1'
export const REMOTE_MANAGE_PROTOCOL_VERSION = 1

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

export interface RemoteRpcRequest {
  id: string
  op: string
  payloadJson?: string
}

export interface RemoteRpcResponse {
  id: string
  ok: boolean
  payloadJson?: string
  error?: string
}

export interface RemoteRpcNotify {
  event: string
  payloadJson?: string
}

export interface RemoteWireFrame {
  v: number
  service: string
  packetId: string
  part: number
  total: number
  data: string
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

export interface RemoteHostHandler {
  waitReady(): Promise<void>
  onRemoteManageConnected?(): void
  onRemoteManageDisconnected?(): void
  summary(): RemoteSummary
  listConfigs(): RemoteConfigMeta[]
  getConfig(configId: string): RemoteGetConfigResult | undefined
  getRuntimeInstance(configId: string): RuntimeInstanceState | undefined
  getConfigFields(configId: string, fields: string[]): RemoteGetFieldsResult
  setConfigField(configId: string, field: string, value: ConfigFieldValue): boolean
  saveConfig(configId: string, displayName: string, config: ConfigJson): boolean
  createDefaultConfig(displayName: string): RemoteCreateDefaultConfigResult | undefined
  importConfig(config: ConfigJson, displayName: string): RemoteCreateDefaultConfigResult | undefined
  deleteConfig(configId: string): boolean
  renameConfig(configId: string, displayName: string): boolean
  startConfig(configId: string): boolean
  stopConfig(configId: string): boolean
  exportToml(configId: string): string | undefined
  getSettings(): RemoteSettingsState
  setSetting(key: string, value: boolean | string): RemoteSettingsState
  requestPermission(kind: string): Promise<RemoteSettingsState>
}

export class RemoteConnectParameters {
  protocol: string = ''
  version: string = ''
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
