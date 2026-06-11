import { ConfigFieldValue, ConfigJson } from '../../config/schema/SchemaConfig'
import { RuntimeInstanceState } from '../../types/runtime/RuntimeTypes'
import {
  RemoteConfigMeta,
  RemoteCreateDefaultConfigResult,
  RemoteGetConfigResult,
  RemoteGetFieldsResult,
  RemoteSettingsState,
  RemoteSummary
} from './RemoteManageDtos'

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
