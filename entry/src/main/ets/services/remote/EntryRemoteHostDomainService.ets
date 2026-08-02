import { deviceInfo } from '@kit.BasicServicesKit'
import { JSON, util } from '@kit.ArkTS'
import easytier from 'easytier-ohrs'
import { AppManager } from '../../AppManager'
import { CLOUD_CONFIG_CHANGED_EVENT } from '../../ConfigSyncUtil'
import { ConfigFieldValue, ConfigJson } from '../../config/schema/SchemaConfig'
import { getDefaultConfig } from '../../config/defaults/ConfigDefaults'
import { RuntimeInstanceState } from '../../types/runtime/RuntimeTypes'
import { normalizeRuntimeMode } from '../../types/runtime/RuntimeModeTypes'
import { getHostname } from '../../util/Conversion'
import { EventHelper } from '../../util/EventHelper'
import { APP_VERSION, CORE_VERSION } from '../../util/info/BuildTime'
import { updateFavorite } from '../form/CommunicationUtil'
import {
  RemoteConfigMeta,
  RemoteCreateDefaultConfigResult,
  RemoteFieldValueResult,
  RemoteGetConfigResult,
  RemoteGetFieldsResult,
  RemoteRuntimeInstanceLite,
  RemoteRuntimeSummary,
  RemoteSettingsState,
  RemoteSummary
} from './RemoteManageTypes'
import { RemoteManageService } from './RemoteManageService'

export class EntryRemoteHostDomainService {
  private remoteSafeUUID(): string {
    let uuid = util.generateRandomUUID()
    while (easytier.getConfig(uuid)) {
      uuid = util.generateRandomUUID()
    }
    return uuid
  }

  private remotePublishConfigChanged(): void {
    AppManager.data.refreshConfigIds()
    EventHelper.emitterPublish(CLOUD_CONFIG_CHANGED_EVENT)
    updateFavorite()
    RemoteManageService.notifyHostSummaryDirty()
  }

  remoteConfigList(): RemoteConfigMeta[] {
    try {
      const entries = JSON.parse(easytier.listConfigs()) as RemoteConfigMeta[]
      return (entries ?? []).map((entry) => {
        const configId = entry.configId
        const displayName = entry.displayName ?? configId
        return {
          configId,
          displayName,
          favorite: entry.favorite,
          running: AppManager.easytier.isRunning(configId)
        } as RemoteConfigMeta
      }).filter((entry) => entry.configId.length > 0)
    } catch (_) {
      return []
    }
  }

  private runtimeDisplayName(instance: RuntimeInstanceState): string {
    const configId = instance.configId
    const instanceId = instance.instanceId
    if (instance.displayName && instance.displayName.length > 0 &&
      instance.displayName !== configId && instance.displayName !== instanceId) {
      return instance.displayName
    }
    return AppManager.easytier.getConfigName(configId) ?? AppManager.easytier.getConfigName(instanceId) ?? '未命名实例'
  }

  private runtimeLite(instance: RuntimeInstanceState): RemoteRuntimeInstanceLite {
    return {
      configId: instance.configId,
      instanceId: instance.instanceId,
      displayName: this.runtimeDisplayName(instance),
      running: instance.running,
      myNodeInfo: instance.myNodeInfo,
      peerCount: instance.peers?.length ?? 0,
      routeCount: instance.routes?.length ?? 0
    }
  }

  remoteRuntimeSummary(): RemoteRuntimeSummary {
    const configs = this.remoteConfigList()
    const runningConfigs = AppManager.easytier.getRunningInstances()
    return {
      configCount: configs.length,
      runningCount: runningConfigs.length,
      runningConfigs: runningConfigs.map((instance) => this.runtimeLite(instance)),
      runtimeDurationText: AppManager.runtimeStats.runtimeDurationText,
      memoryUsageText: AppManager.runtimeStats.memoryUsageText
    }
  }

  remoteSettings(): RemoteSettingsState {
    return {
      // 保留字段用于兼容旧版近场控制台；运行载体现在固定为 VpnExtensionAbility。
      ext_mode: true,
      background_keep_alive_mode: normalizeRuntimeMode(AppManager.uiState.background_keep_alive_mode),
      dev: AppManager.uiState.dev,
      vpn_routes: AppManager.uiState.vpn_routes,
      force_global: AppManager.uiState.force_global,
      dns: AppManager.uiState.dns,
      core_log: AppManager.uiState.core_log,
      debug_log: AppManager.uiState.debug_log,
      distributePerm: AppManager.permission.isGetDistributePerm()
    }
  }

  remoteSummary(): RemoteSummary {
    return {
      appVersion: APP_VERSION,
      coreVersion: CORE_VERSION,
      deviceName: deviceInfo.productModel,
      sdkApiVersion: deviceInfo.sdkApiVersion,
      configs: this.remoteConfigList(),
      runtime: this.remoteRuntimeSummary(),
      settings: this.remoteSettings()
    }
  }

  remoteGetConfig(configId: string): RemoteGetConfigResult | undefined {
    if (!configId) {
      return undefined
    }
    const raw = easytier.getConfig(configId)
    if (!raw) {
      return undefined
    }
    try {
      const rawText: string = raw as string
      const config: ConfigJson = JSON.parse(rawText) as ConfigJson
      return {
        configId,
        displayName: easytier.getConfigDisplayNameById(configId) ?? configId,
        config
      }
    } catch (_) {
      return undefined
    }
  }

  remoteGetRuntimeInstance(configId: string): RuntimeInstanceState | undefined {
    if (!configId) {
      return undefined
    }
    const instance = AppManager.easytier.getRunningInstance(configId)
    if (!instance) {
      return undefined
    }
    return {
      configId: instance.configId,
      instanceId: instance.instanceId,
      displayName: this.runtimeDisplayName(instance),
      running: instance.running,
      tunRequired: instance.tunRequired,
      tunAttached: instance.tunAttached,
      magicDnsEnabled: instance.magicDnsEnabled,
      needExitNode: instance.needExitNode,
      myNodeInfo: instance.myNodeInfo,
      routes: instance.routes ?? [],
      peers: instance.peers ?? []
    }
  }

  remoteGetConfigFields(configId: string, fields: string[]): RemoteGetFieldsResult {
    return {
      values: fields.map((field) => {
        const rawValue = easytier.getConfigField(configId, field)
        const result: RemoteFieldValueResult = {
          field,
          rawValue: rawValue ?? undefined,
          found: rawValue !== null && rawValue !== undefined
        }
        return result
      })
    }
  }

  remoteSetConfigField(configId: string, field: string, value: ConfigFieldValue): boolean {
    if (!configId || !field) {
      return false
    }
    const ok = easytier.setConfigField(configId, field, JSON.stringify(value ?? null))
    if (ok) {
      this.remotePublishConfigChanged()
    }
    return ok
  }

  remoteSaveConfig(configId: string, displayName: string, config: ConfigJson): boolean {
    if (!configId || !config) {
      return false
    }
    const ok = easytier.saveConfig(configId, displayName || configId, JSON.stringify(config))
    if (ok) {
      this.remotePublishConfigChanged()
    }
    return ok
  }

  remoteCreateDefaultConfig(displayName: string): RemoteCreateDefaultConfigResult | undefined {
    const config: ConfigJson = getDefaultConfig(getHostname())
    const configId = this.remoteSafeUUID()
    config.instance_id = configId
    const name = displayName && displayName.length > 0 ? displayName : 'EasyTier'
    if (!this.remoteSaveConfig(configId, name, config)) {
      return undefined
    }
    return { configId, displayName: name, config }
  }

  remoteImportConfig(config: ConfigJson, displayName: string): RemoteCreateDefaultConfigResult | undefined {
    try {
      const configText: string = JSON.stringify(config)
      const imported: ConfigJson = JSON.parse(configText) as ConfigJson
      const configId = this.remoteSafeUUID()
      imported.instance_id = configId
      const name = displayName && displayName.length > 0 ? displayName : configId
      if (!this.remoteSaveConfig(configId, name, imported)) {
        return undefined
      }
      return { configId, displayName: name, config: imported }
    } catch (_) {
      return undefined
    }
  }

  remoteDeleteConfig(configId: string): boolean {
    const ok = AppManager.data.delConfig(configId)
    if (ok) {
      this.remotePublishConfigChanged()
    }
    return ok
  }

  remoteRenameConfig(configId: string, displayName: string): boolean {
    if (!configId || !displayName) {
      return false
    }
    const ok = easytier.renameStoredConfig(configId, displayName)
    if (ok) {
      this.remotePublishConfigChanged()
    }
    return ok
  }

  remoteSetSetting(key: string, value: boolean | string): RemoteSettingsState {
    switch (key) {
      case 'runtime_mode':
        if (AppManager.easytier.runningNetworks.size === 0 && typeof value === 'string') {
          AppManager.uiState.background_keep_alive_mode = normalizeRuntimeMode(value)
        }
        break
      case 'ext_mode':
        // 兼容旧客户端写入；Extension-only 模式不可关闭。
        break
      case 'background_keep_alive_mode':
        if (AppManager.easytier.runningNetworks.size === 0 && typeof value === 'string') {
          AppManager.uiState.background_keep_alive_mode = normalizeRuntimeMode(value)
        }
        break
      case 'dev':
        AppManager.uiState.dev = Boolean(value)
        break
      case 'vpn_routes':
        AppManager.uiState.vpn_routes = Boolean(value)
        break
      case 'force_global':
        AppManager.uiState.force_global = Boolean(value)
        break
      case 'core_log':
        AppManager.uiState.core_log = Boolean(value)
        break
      case 'debug_log':
        AppManager.uiState.debug_log = Boolean(value)
        break
      case 'dns':
        if (typeof value === 'string') {
          AppManager.uiState.dns = value
        }
        break
    }
    return this.remoteSettings()
  }

  async remoteRequestPermission(kind: string): Promise<RemoteSettingsState> {
    if (kind === 'distributed') {
      await AppManager.permission.requestDistributePerm()
    }
    await AppManager.permission.updatePermStatus()
    return this.remoteSettings()
  }
}
