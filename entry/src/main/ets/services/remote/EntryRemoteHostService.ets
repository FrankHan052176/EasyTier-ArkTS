import easytier from 'easytier-ohrs'
import { AppManager } from '../../AppManager'
import { ConfigFieldValue, ConfigJson } from '../../config/schema/SchemaConfig'
import { RuntimeInstanceState } from '../../types/runtime/RuntimeTypes'
import {
  RemoteConfigMeta,
  RemoteCreateDefaultConfigResult,
  RemoteGetConfigResult,
  RemoteGetFieldsResult,
  RemoteHostHandler,
  RemoteSettingsState,
  RemoteSummary
} from './RemoteManageTypes'

export interface EntryRemoteHostDelegate {
  remoteWaitReady(): Promise<void>
  remoteManageConnected(): void
  remoteManageDisconnected(): void
  remoteSummary(): RemoteSummary
  remoteConfigList(): RemoteConfigMeta[]
  remoteGetConfig(configId: string): RemoteGetConfigResult | undefined
  remoteGetRuntimeInstance(configId: string): RuntimeInstanceState | undefined
  remoteGetConfigFields(configId: string, fields: string[]): RemoteGetFieldsResult
  remoteSetConfigField(configId: string, field: string, value: ConfigFieldValue): boolean
  remoteSaveConfig(configId: string, displayName: string, config: ConfigJson): boolean
  remoteCreateDefaultConfig(displayName: string): RemoteCreateDefaultConfigResult | undefined
  remoteImportConfig(config: ConfigJson, displayName: string): RemoteCreateDefaultConfigResult | undefined
  remoteDeleteConfig(configId: string): boolean
  remoteRenameConfig(configId: string, displayName: string): boolean
  remoteSettings(): RemoteSettingsState
  remoteSetSetting(key: string, value: boolean | string): RemoteSettingsState
  remoteRequestPermission(kind: string): Promise<RemoteSettingsState>
}

class EntryRemoteHostHandler implements RemoteHostHandler {
  private delegate: EntryRemoteHostDelegate

  constructor(delegate: EntryRemoteHostDelegate) {
    this.delegate = delegate
  }

  async waitReady(): Promise<void> {
    await this.delegate.remoteWaitReady()
  }

  onRemoteManageConnected(): void {
    this.delegate.remoteManageConnected()
  }

  onRemoteManageDisconnected(): void {
    this.delegate.remoteManageDisconnected()
  }

  summary(): RemoteSummary {
    return this.delegate.remoteSummary()
  }

  listConfigs(): RemoteConfigMeta[] {
    return this.delegate.remoteConfigList()
  }

  getConfig(configId: string): RemoteGetConfigResult | undefined {
    return this.delegate.remoteGetConfig(configId)
  }

  getRuntimeInstance(configId: string): RuntimeInstanceState | undefined {
    return this.delegate.remoteGetRuntimeInstance(configId)
  }

  getConfigFields(configId: string, fields: string[]): RemoteGetFieldsResult {
    return this.delegate.remoteGetConfigFields(configId, fields)
  }

  setConfigField(configId: string, field: string, value: ConfigFieldValue): boolean {
    return this.delegate.remoteSetConfigField(configId, field, value)
  }

  saveConfig(configId: string, displayName: string, config: ConfigJson): boolean {
    return this.delegate.remoteSaveConfig(configId, displayName, config)
  }

  createDefaultConfig(displayName: string): RemoteCreateDefaultConfigResult | undefined {
    return this.delegate.remoteCreateDefaultConfig(displayName)
  }

  importConfig(config: ConfigJson, displayName: string): RemoteCreateDefaultConfigResult | undefined {
    return this.delegate.remoteImportConfig(config, displayName)
  }

  deleteConfig(configId: string): boolean {
    return this.delegate.remoteDeleteConfig(configId)
  }

  renameConfig(configId: string, displayName: string): boolean {
    return this.delegate.remoteRenameConfig(configId, displayName)
  }

  startConfig(configId: string): boolean {
    return AppManager.easytier.start(configId)
  }

  stopConfig(configId: string): boolean {
    return AppManager.easytier.stopConfig(configId)
  }

  exportToml(configId: string): string | undefined {
    return easytier.exportToml(configId) ?? undefined
  }

  getSettings(): RemoteSettingsState {
    return this.delegate.remoteSettings()
  }

  setSetting(key: string, value: boolean | string): RemoteSettingsState {
    return this.delegate.remoteSetSetting(key, value)
  }

  async requestPermission(kind: string): Promise<RemoteSettingsState> {
    return this.delegate.remoteRequestPermission(kind)
  }
}

export class EntryRemoteHostService {
  static createHandler(delegate: EntryRemoteHostDelegate): RemoteHostHandler {
    return new EntryRemoteHostHandler(delegate)
  }
}
