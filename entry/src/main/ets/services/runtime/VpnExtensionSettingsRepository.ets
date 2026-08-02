import { Context } from '@kit.AbilityKit'
import { preferences } from '@kit.ArkData'

const SETTINGS_PREFERENCES_NAME = 'EasyTierPreferences'
const APP_FILTER_PREFERENCES_NAME = 'EasyTierBlackListApp'

interface StoredAppFilterEntry {
  enable?: boolean
}

export interface VpnExtensionRuntimeSettings {
  whiteList: boolean
  blackList: string[]
  dns: string
  dev: boolean
  forceGlobal: boolean
  coreLog: boolean
  debugLog: boolean
}

export class VpnExtensionSettingsRepository {
  static load(context: Context): VpnExtensionRuntimeSettings {
    const settings = preferences.getPreferencesSync(context, { name: SETTINGS_PREFERENCES_NAME })
    return {
      whiteList: settings.getSync('white_list', false).valueOf() as boolean,
      blackList: VpnExtensionSettingsRepository.loadEnabledAppFilters(context),
      dns: settings.getSync('dns', '').valueOf() as string,
      dev: settings.getSync('dev', false).valueOf() as boolean,
      forceGlobal: settings.getSync('force_global', true).valueOf() as boolean,
      coreLog: settings.getSync('core_log', false).valueOf() as boolean,
      debugLog: settings.getSync('debug_log', false).valueOf() as boolean
    }
  }

  private static loadEnabledAppFilters(context: Context): string[] {
    const store = preferences.getPreferencesSync(context, { name: APP_FILTER_PREFERENCES_NAME })
    let values: ESObject = store.getAllSync()
    const enabledPackages: string[] = []
    for (const packageName of Object.keys(values)) {
      const entry = values[packageName] as StoredAppFilterEntry
      if (entry.enable !== false) {
        enabledPackages.push(packageName)
      }
    }
    return enabledPackages
  }
}
