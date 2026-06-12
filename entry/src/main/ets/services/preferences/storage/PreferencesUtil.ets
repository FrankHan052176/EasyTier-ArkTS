import { preferences } from '@kit.ArkData';
import { Context } from '@kit.AbilityKit';
import easytier from 'easytier-ohrs';
import { AppManager } from '../../../AppManager';
import { Logger, LogLocate } from '../../../shared/logging/Logger';
import { JSON, util } from '@kit.ArkTS';
import { AppInfo } from '../../../components/sheet/BlackList';
import { connection } from '@kit.NetworkKit';
import { syncWholeConfig } from '../../../ConfigSyncUtil';
import { getDefaultConfig } from '../../../config/defaults/ConfigDefaults';
import { ConfigFieldValue, ConfigJson } from '../../../config/schema/SchemaConfig';
import { release } from '../../../util/info/ArtifactsType';
import { EventHelper } from '../../../util/EventHelper';
import { FAVORITE_CARD_REFRESH_EVENT } from '../../form/FavoriteCardState';
import { buildTunRoutes, shouldBuildPreferenceVpnRoutes } from '../../tun/TunConfigBuilder';
import {
  BACKGROUND_KEEP_ALIVE_DATA_TRANSFER,
  normalizeBackgroundKeepAliveMode
} from '../../../types/runtime/BackgroundKeepAliveTypes';

const easytier_release = easytier

interface StoredConfigMetaLite {
  configId: string
  favorite: boolean
}

const defaultSequence = 'Instances_0_0_2_1|Favorite_0_1_1_1|Logs_1_1_1_1|QQ_0_2_1_1|SharedPeers_1_2_1_1'

@LogLocate("PreferenceUtil")
@ObservedV2
export class PreferenceUtil {
  @Trace globalConfigs: preferences.Preferences | undefined
  @Trace preferences: preferences.Preferences | undefined
  @Trace black_list_preference: preferences.Preferences | undefined
  @Trace card_list_preference: preferences.Preferences | undefined
  @Trace black_list_apps: Map<string, AppInfo> = new Map()
  @Trace white_list_apps: Map<string, AppInfo> = new Map()
  
  public isInit: boolean = false
  private initialized: boolean = false

  private getStoredFavoriteConfigId(): string | undefined {
    try {
      const entries = JSON.parse(easytier.listConfigs()) as StoredConfigMetaLite[]
      return entries.find((entry) => entry.favorite)?.configId
    } catch (_) {
      return undefined
    }
  }

  private reconcileFavoritePreference(preferredFavorite: string | undefined): void {
    const storedFavorite = this.getStoredFavoriteConfigId()
    if (storedFavorite) {
      AppManager.uiState.favorite = storedFavorite
      return
    }
    if (preferredFavorite && easytier.getConfig(preferredFavorite) && easytier.setConfigFavorite(preferredFavorite, true)) {
      AppManager.uiState.favorite = preferredFavorite
      return
    }
    AppManager.uiState.favorite = undefined
  }

  private decodeLegacyConfigName(rawName: Object | undefined): string | undefined {
    if (typeof rawName === 'string') {
      return rawName
    }
    if (rawName instanceof Uint8Array) {
      const decoder = util.TextDecoder.create('utf-8', { fatal: false, ignoreBOM: true })
      return decoder.decodeToString(rawName, { stream: false })
    }
    return undefined
  }

  private normalizeLegacyConfigValue(rawValue: Object | undefined): ConfigFieldValue | undefined {
    if (rawValue === undefined || rawValue === null) {
      return rawValue as ConfigFieldValue
    }
    if (typeof rawValue === 'string' || typeof rawValue === 'number' || typeof rawValue === 'boolean') {
      return rawValue as ConfigFieldValue
    }
    try {
      return JSON.parse(JSON.stringify(rawValue)) as ConfigFieldValue
    } catch (_) {
      return undefined
    }
  }

  private clearLegacyPreferenceStore(store: preferences.Preferences): void {
    const all:ESObject = store.getAllSync() as ESObject
    Object.keys(all).forEach((key) => {
      store.deleteSync(key)
    })
    store.flushSync()
  }

  private async deleteLegacyPreferenceConfig(context: Context, legacyConfigIdPreferences: preferences.Preferences,
    configId: string, legacyConfigPreference?: preferences.Preferences): Promise<void> {
    const store = legacyConfigPreference ?? preferences.getPreferencesSync(context, { name: configId })
    this.clearLegacyPreferenceStore(store)
    legacyConfigIdPreferences.deleteSync(configId)
    await preferences.deletePreferences(context, configId)
  }

  async clearLegacyPreferenceSources(context: Context): Promise<void> {
    const legacyConfigIdPreferences = preferences.getPreferencesSync(context, { name: 'EasyTierConfigIDs' })
    const legacyConfigIds = Object.keys(legacyConfigIdPreferences.getAllSync() as ESObject)
    for (const configId of legacyConfigIds) {
      try {
        await this.deleteLegacyPreferenceConfig(context, legacyConfigIdPreferences, configId)
      } catch (error) {
        Logger.error(`clear legacy config source failed id=${configId} err=${JSON.stringify(error)}`, this)
      }
    }
    legacyConfigIdPreferences.flushSync()
    if (Object.keys(legacyConfigIdPreferences.getAllSync() as ESObject).length === 0) {
      await preferences.deletePreferences(context, 'EasyTierConfigIDs')
    }
  }

  private async migrateLegacyPreferenceConfigs(context: Context): Promise<void> {
    const legacyConfigIdPreferences = preferences.getPreferencesSync(context, { name: 'EasyTierConfigIDs' })
    const allLegacyConfigs:ESObject = legacyConfigIdPreferences.getAllSync()
    const legacyConfigIds = Object.keys(allLegacyConfigs)
    if (legacyConfigIds.length === 0) {
      return
    }

    Logger.info(`migrateLegacyPreferenceConfigs found ${legacyConfigIds.length} legacy configs`, this)
    for (const configId of legacyConfigIds) {
      try {
        const displayName = this.decodeLegacyConfigName(allLegacyConfigs[configId] as ESObject) ?? configId
        const legacyConfigPreference = preferences.getPreferencesSync(context, { name: configId })
        let migrated = true
        if (!easytier.getConfig(configId)) {
          const rawConfig:ESObject = legacyConfigPreference.getAllSync()
          const config:ESObject = getDefaultConfig('')
          Object.keys(rawConfig).forEach((field) => {
            const normalized: ConfigFieldValue | undefined = this.normalizeLegacyConfigValue(rawConfig[field] as Object)
            if (normalized !== undefined) {
              config[field] = normalized as ConfigFieldValue
            }
          })
          config.instance_id = configId
          migrated = syncWholeConfig(configId, displayName, config as ConfigJson)
        }
        if (!migrated) {
          Logger.error(`migrate legacy config save failed id=${configId}`, this)
          continue
        }
        await this.deleteLegacyPreferenceConfig(context, legacyConfigIdPreferences, configId, legacyConfigPreference)
      } catch (error) {
        Logger.error(`migrate legacy config failed id=${configId} err=${JSON.stringify(error)}`, this)
      }
    }
    legacyConfigIdPreferences.flushSync()
    if (Object.keys(legacyConfigIdPreferences.getAllSync() as ESObject).length === 0) {
      await preferences.deletePreferences(context, 'EasyTierConfigIDs')
    }
    AppManager.data.refreshConfigIds()
  }

  async init(context: Context) {
    if (this.initialized) {
      return
    }
    this.isInit = true
    let completed = false
    try {
      if (!context.filesDir || context.filesDir.length === 0) {
        throw new Error('context.filesDir is empty')
      }
      if (!easytier.initConfigStore(context.filesDir)) {
        throw new Error(`initConfigStore failed filesDir=${context.filesDir}`)
      }
      this.preferences = preferences.getPreferencesSync(context, { name: 'EasyTierPreferences' })
      
      const s = AppManager.uiState;
      // 从磁盘加载值到 UIState
      s.core_log = this.preferences.getSync("core_log",
        this.preferences.getSync("show_log", false).valueOf() as boolean).valueOf() as boolean;
      s.debug_log = this.preferences.getSync("debug_log", false).valueOf() as boolean;
      s.vpn_routes = this.preferences.getSync("vpn_routes", false).valueOf() as boolean;
      s.dev = this.preferences.getSync("dev", false).valueOf() as boolean;
      s.force_global = this.preferences.getSync("force_global", true).valueOf() as boolean;
      s.white_list = this.preferences.getSync("white_list", false).valueOf() as boolean;
      s.dns = this.preferences.getSync("dns", "").valueOf() as string;
      s.noOldData = this.preferences.getSync("noOldData", false).valueOf() as boolean;
      s.holding_detector = this.preferences.getSync("holding_detector", false).valueOf() as boolean;
      s.vault_mode = this.preferences.getSync("vault_mode", false).valueOf() as boolean;
      s.ext_mode = this.preferences.getSync("ext_mode", false).valueOf() as boolean;
      s.ask_dlp = this.preferences.getSync("ask_dlp", false).valueOf() as boolean;
      s.cloud_auto_sync = this.preferences.getSync("cloud_auto_sync", false).valueOf() as boolean;
      s.background_keep_alive_mode = normalizeBackgroundKeepAliveMode(this.preferences.getSync("background_keep_alive_mode",
        BACKGROUND_KEEP_ALIVE_DATA_TRANSFER).valueOf() as string);
      s.raw_comp_sequence = this.preferences.getSync("raw_comp_sequence", defaultSequence).valueOf() as string;
      s.help2 = this.preferences.getSync("help2", true).valueOf() as boolean;

      // 记录启动时内核相关的状态
      s.inittedCoreLog = s.core_log;
      easytier.configureLogManager(s.core_log, s.debug_log)

      const preferredSelected = this.preferences!.getSync("selected", "").toString() || undefined
      const preferredFavorite = this.preferences!.getSync("favorite", "").toString() || undefined
      s.selected = preferredSelected

      await this.migrateLegacyPreferenceConfigs(context)
      this.reconcileFavoritePreference(preferredFavorite)

      this.globalConfigs = preferences.getPreferencesSync(context, { name: 'EasyTierGlobalConfigs' })
      await new Promise<void>((resolve) => {
        this.globalConfigs!.getAll((err, obj) => {
          if (err) {
            Logger.error("failed to read global configs"+JSON.stringify(err), this)
            resolve()
            return
          }
          try {
            for (const field of Object.keys(obj)) {
              let esObj: ESObject = obj
              let value: string[] = esObj[field]
              AppManager.data.initDataSource(field, value)
            }
          } catch (e) {
            Logger.error("init globalConfigs callback error: " + JSON.stringify(e), this)
          }
          resolve()
        })
      })

      this.black_list_preference = preferences.getPreferencesSync(context, { name: 'EasyTierBlackListApp' })
      this.updateBlackListApps()
      this.card_list_preference = preferences.getPreferencesSync(context, { name: 'EasyTierCardList' })
      this.initialized = true
      completed = true
      
    } catch (e) {
      Logger.error("init error: " + JSON.stringify(e), this)
      if (e instanceof Error) {
        throw e
      }
      throw new Error(`PreferenceUtil init error: ${JSON.stringify(e)}`)
    } finally {
      setTimeout(() => {
        this.isInit = false
        if (completed && !AppManager.uiState.noOldData) {
          AppManager.uiState.noOldData = true
        }
      }, 100)
    }

    if (completed && AppManager.uiState.core_log) {
      if (AppManager.uiState.inittedGitCore) {
        easytier.initTracingSubscriber()
      }else {
        easytier_release.initTracingSubscriber()
      }
    }
  }

  updateSequence(sequence: string) {
    AppManager.uiState.raw_comp_sequence = sequence;
  }

  refreshFavoriteFromStore(): void {
    AppManager.uiState.favorite = this.getStoredFavoriteConfigId()
    EventHelper.emitterPublish(FAVORITE_CARD_REFRESH_EVENT)
  }

  getAppInfo(pkgName: string): AppInfo | undefined {
    return this.black_list_apps.get(pkgName)
	}

  setAppInfo(pkgName: string, name: string, icon: string) {
    let info = new AppInfo(pkgName, name, icon)
    try {
      this.black_list_preference!.putSync(pkgName, info)
      this.black_list_preference!.flushSync()
      if (!this.black_list_apps.has(pkgName)) {
        this.black_list_apps.set(pkgName, info)
      }else {
        this.black_list_apps.get(pkgName)!.name = name
        this.black_list_apps.get(pkgName)!.icon = icon
      }
    } catch (e) {
      Logger.error("setAppInfo error: " + JSON.stringify(e), this)
    }
  }

  private updateBlackListApps() {
    try {
      let obj: ESObject = this.black_list_preference!.getAllSync()
      for (const pkgName of Object.keys(obj)) {
        let info = obj[pkgName] as AppInfo
        this.black_list_apps.set(pkgName, info)
      }
    } catch (e) {
      Logger.error("updateBlackListApps error: " + JSON.stringify(e), this)
    }
  }

  delAppInfo(pkgName: string) {
    try {
      this.black_list_preference!.deleteSync(pkgName)
      this.black_list_preference!.flushSync()
      this.black_list_apps.delete(pkgName)
    } catch (e) {
      Logger.error("delAppInfo error: " + JSON.stringify(e), this)
    }
  }

  updateAppInfo(info: AppInfo) {
    try {
      this.black_list_preference!.putSync(info.pkgName, info)
      this.black_list_preference!.flushSync()
    } catch (e) {
      Logger.error("updateAppInfo error: " + JSON.stringify(e), this)
    }
  }

  getBlackList(): string[] {
    let list: string[] = []
    this.black_list_apps.forEach((value, key) => {
      if (value.enable) {
        list.push(key)
      }
    })
    return list
  }

  getCardList(): string[] {
    if (this.card_list_preference) {
      try {
        return this.card_list_preference.getSync("card_list", []) as string []
      } catch (e) {
        Logger.error("getCardList error: " + JSON.stringify(e), this)
        return []
      }
    }
    return []
  }

  cleanCardList(list: string[]) {
    if (this.card_list_preference) {
      try {
        let formList = this.card_list_preference.getSync("card_list", []) as string []
        list.forEach((value) => {
          let index = formList.indexOf(value)
          if (index > -1) {
            formList.splice(index, 1)
          }
        })
        this.card_list_preference.putSync("card_list", formList)
        this.card_list_preference.flushSync()
      } catch (e) {
        Logger.error("cleanCardList error: " + JSON.stringify(e), this)
      }
    }
  }

  addCardId(formId: string) {
    if (this.card_list_preference) {
      try {
        const list = this.getCardList()
        if (!list.includes(formId)) {
          list.push(formId)
          this.card_list_preference.putSync("card_list", list)
          this.card_list_preference.flushSync()
        }
      } catch (e) {
        Logger.error("addCardId error: " + JSON.stringify(e), this)
      }
    }
  }

  delCardId(formId: string) {
    if (this.card_list_preference) {
      try {
        const list = this.getCardList()
        const index = list.indexOf(formId)
        if (index > -1) {
          list.splice(index, 1)
          this.card_list_preference.putSync("card_list", list)
          this.card_list_preference.flushSync()
        }
      } catch (e) {
        Logger.error("delCardId error: " + JSON.stringify(e), this)
      }
    }
  }

  getVpnCfgRoutes(ip: string, magicDNS: boolean, needExitNode: boolean, customRoutes?: string[]): connection.RouteInfo[] | undefined {
    return buildTunRoutes({
      ip,
      magicDNS,
      needExitNode,
      routeStrings: customRoutes,
      enabled: shouldBuildPreferenceVpnRoutes(AppManager.uiState.vpn_routes)
    }).routes
	}
}
