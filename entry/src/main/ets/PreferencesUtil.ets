import { preferences, sendablePreferences, ValueType } from '@kit.ArkData';
import { Context } from '@kit.AbilityKit';
import easytier from 'easytier-ohrs';
import easytier_release from 'easytier-release';
import { AppManager } from './AppManager';
import { NetworkConfig, PortForwardConfig } from './protobuf/api_manage';
import { Logger, LogLocate } from './util/Logger';
import { buffer, collections, JSON, taskpool, util } from '@kit.ArkTS';
import { SafePortForwardConfig } from './class/SafeProtoClass';
import { ContentUtil } from './ContentUtil';
import { AppInfo } from './components/sheet/BlackList';
import { BusinessError, deviceInfo } from '@kit.BasicServicesKit';
import { connection } from '@kit.NetworkKit';
import { stringArr2RouteArr } from './util/Conversion';
import { release } from './util/info/ArtifactsType';

const defaultSequence = 'Instances_0_0_2_1|Favorite_0_1_1_1|Logs_1_1_1_1|QQ_0_2_1_1|SharedPeers_1_2_1_1'

@Concurrent
async function readConfigFromPreference(data: sendablePreferences.Preferences): Promise<string> {
  let rawConfig = data.getAllSync() as Record<string, Object>
  let config = ContentUtil.getDefaultConfig("")
  for (let key of Object.keys(rawConfig)) {
    if (rawConfig[key] instanceof collections.Array) {
      if (key === 'port_forwards') {
        let value = rawConfig[key] as collections.Array<SafePortForwardConfig>
        let arr = new Array<PortForwardConfig>()
        value.forEach((s) => {
          arr.push(s.toInterface())
        })
        config[key] = arr
      } else {
        let value = rawConfig[key] as collections.Array<string>
        let arr = new Array<string>()
        value.forEach((s) => {
          arr.push(s)
        })
        config[key] = arr
      }
    } else {
      config[key] = rawConfig[key]
    }
  }
  return JSON.stringify(config);
}

@LogLocate("PreferenceUtil")
@ObservedV2
export class PreferenceUtil {
  @Trace configPreferences: Map<string, sendablePreferences.Preferences> = new Map()
  @Trace configIDPreferences: preferences.Preferences | undefined
  @Trace globalConfigs: preferences.Preferences | undefined
  @Trace preferences: preferences.Preferences | undefined
  @Trace black_list_preference: preferences.Preferences | undefined
  @Trace card_list_preference: preferences.Preferences | undefined
  @Trace black_list_apps: Map<string, AppInfo> = new Map()
  @Trace white_list_apps: Map<string, AppInfo> = new Map()
  
  public isInit: boolean = false
  context: Context | undefined = undefined
  private initialized: boolean = false

  async init(context: Context) {
    if (this.initialized) {
      return
    }
    this.initialized = true
    this.isInit = true
    this.context = context
    try {
      this.preferences = preferences.getPreferencesSync(context, { name: 'EasyTierPreferences' })
      this.configIDPreferences = preferences.getPreferencesSync(context, { name: 'EasyTierConfigIDs' })
      
      const s = AppManager.uiState;
      // 从磁盘加载值到 UIState
      s.show_log = this.preferences.getSync("show_log", false).valueOf() as boolean;
      s.vpn_routes = this.preferences.getSync("vpn_routes", false).valueOf() as boolean;
      s.dev = this.preferences.getSync("dev", false).valueOf() as boolean;
      s.force_global = this.preferences.getSync("force_global", true).valueOf() as boolean;
      s.white_list = this.preferences.getSync("white_list", false).valueOf() as boolean;
      s.dns = this.preferences.getSync("dns", "").valueOf() as string;
      s.noOldData = this.preferences.getSync("noOldData", false).valueOf() as boolean;
      s.holding_detector = this.preferences.getSync("holding_detector", false).valueOf() as boolean;
      s.git_core = this.preferences.getSync("git_core", !release).valueOf() as boolean;
      s.vault_mode = this.preferences.getSync("vault_mode", false).valueOf() as boolean;
      s.ext_mode = this.preferences.getSync("ext_mode", false).valueOf() as boolean;
      s.ask_dlp = this.preferences.getSync("ask_dlp", false).valueOf() as boolean;
      s.raw_comp_sequence = this.preferences.getSync("raw_comp_sequence", defaultSequence).valueOf() as string;
      s.help2 = this.preferences.getSync("help2", true).valueOf() as boolean;

      // 记录启动时内核相关的状态
      s.inittedGitCore = release ? s.git_core : true;
      s.inittedLog = s.show_log;

      await new Promise<void>((resolve) => {
        this.configIDPreferences!.getAll(async (err, obj) => {
          if (err) {
            Logger.error("failed to read all configs"+JSON.stringify(err), this)
            resolve()
            return
          }
          try {
            let keys = Object.keys(obj)
            let loadTasks: Promise<void>[] = []
            for (const field of keys) {
              let esObj: ESObject = obj
              let nameBytes = esObj[field] as Uint8Array
              let preference = sendablePreferences.getPreferencesSync(context, { name: field })
              this.configPreferences.set(field, preference)
              loadTasks.push(this.readConfig(field, nameBytes, preference))
            }
            await Promise.all(loadTasks)
            
            s.selected = this.preferences!.getSync("selected", "").toString() || undefined;
            s.favorite = this.preferences!.getSync("favorite", "").toString() || undefined;
          } catch (e) {
            Logger.error("init configIDPreferences callback error: " + JSON.stringify(e), this)
          }
          resolve()
        })
      })

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
      
    } catch (e) {
      Logger.error("init error: " + JSON.stringify(e), this)
    }

    if (AppManager.uiState.show_log) {
      if (AppManager.uiState.inittedGitCore) {
        easytier.initTracingSubscriber()
      }else {
        easytier_release.initTracingSubscriber()
      }
    }

    setTimeout(() => {
      this.isInit = false
      if (!AppManager.uiState.noOldData) {
        AppManager.uiState.noOldData = true
      }
    }, 100)
  }

  updateSequence(sequence: string) {
    AppManager.uiState.raw_comp_sequence = sequence;
  }

  addConfig(uuid: string, name: string, config: NetworkConfig) {
    try {
      this.configIDPreferences?.putSync(uuid, new Uint8Array(buffer.from(name, 'utf-8').buffer))
      this.configIDPreferences?.flushSync()
      let preference = sendablePreferences.getPreferencesSync(this.context!, { name: uuid })
      Object.entries(config)
        .forEach((value: [string, undefined | Array<string | PortForwardConfig> | string | boolean | number]) => {
          if (value[1]) {
            if (Array.isArray(value[1])) {
              if (value[0] === 'port_forwards') {
                let arr = value[1] as PortForwardConfig[]
                let safeArr = new collections.Array<SafePortForwardConfig>()
                arr.forEach((v) => {
                  safeArr.push(new SafePortForwardConfig(v))
                })
                preference.putSync(value[0], safeArr)
              } else {
                let arr = value[1] as string[]
                let safeArr = new collections.Array<string>(...arr)
                preference.putSync(value[0], safeArr)
              }
            } else {
              preference.putSync(value[0], value[1])
            }
          }
        })
      preference.flushSync()
      this.configPreferences.set(uuid, preference)
    } catch (error) {
      Logger.error("Failed to add config", this)
    }
  }

  private async readConfig(field: string, nameBytes: Uint8Array, preference: sendablePreferences.Preferences) {
    let textDecoderOptions: util.TextDecoderOptions = {
      fatal: false,
      ignoreBOM: true
    }
    let decodeToStringOptions: util.DecodeToStringOptions = {
      stream: false
    }
    let textDecoder = util.TextDecoder.create('utf-8', textDecoderOptions);
    let name = textDecoder.decodeToString(new Uint8Array(nameBytes), decodeToStringOptions);
    AppManager.uiState.configUUIDNameMap.set(field, name)
    const task: taskpool.Task = new taskpool.Task(readConfigFromPreference, preference);
    return taskpool.execute(task).then((value: object) => {
      try {
        let config = value.toString()
        let obj = JSON.parse(config) as NetworkConfig
        AppManager.data.configUUIDMap.set(field, obj)
        AppManager.preference.addConfig(field, name, obj)
      } catch (e) {
        Logger.error(`readConfig parse error: ${JSON.stringify(e)}`, this)
      }
    }).catch((e: BusinessError) => {
      Logger.error(`readConfig task error: ${e.code}, ${e.message}`, this)
    })
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
            formList.splice(index)
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

  getVpnCfgRoutes(ip: string, magicDNS: boolean, needExitNode: boolean): connection.RouteInfo[] | undefined {
		return AppManager.uiState.vpn_routes || deviceInfo.sdkApiVersion >= 20 ? stringArr2RouteArr(ip, magicDNS, needExitNode) : undefined;
	}
}
