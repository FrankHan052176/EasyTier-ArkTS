import { preferences, sendablePreferences, ValueType } from '@kit.ArkData';
import easytier from 'easytier-ohrs';
import { AppManager } from './AppManager';
import { NetworkConfig, PortForwardConfig } from './protobuf/api_manage';
import { Logger, LogLocate } from './util/Logger';
import { buffer, collections, JSON, taskpool, util } from '@kit.ArkTS';
import { SafePortForwardConfig } from './class/SafeProtoClass';
import { ContentUtil } from './ContentUtil';
import { AppInfo } from './components/sheet/BlackList';

const defaultSequence = 'Instances_0_0_2_1|Favorite_0_1_1_1|Logs_1_1_1_1|QQ_0_2_1_1|SharedPeers_1_2_1_1'

@Concurrent
async function readConfigFromPreference(id: String, data: sendablePreferences.Preferences): Promise<string> {
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
  @Trace private black_list_preference: preferences.Preferences | undefined
  @Trace black_list_apps: Map<string, AppInfo> = new Map()
  @Trace show_log: boolean = false
  @Trace raw_comp_sequence: string = defaultSequence
  @Trace vpn_routes: boolean = false
  @Trace dev: boolean = false
  @Trace dns: string = ""
  @Trace noOldData: boolean = false
  @Trace holding_detector: boolean = false
  inittedLog: boolean = false
  isInit: boolean = true

  init(context: Context) {
    this.preferences = preferences.getPreferencesSync(context, { name: 'EasyTierPreferences' })
    this.configIDPreferences = preferences.getPreferencesSync(context, { name: 'EasyTierConfigIDs' })
    this.configIDPreferences.getAll(async (err, obj) => {
      let start = Date.now()
      if (err) {
        Logger.error(JSON.stringify(err), this)
        return
      }
      let keys = Object.keys(obj)
      for (const field of keys) {
        let esObj: ESObject = obj
        let nameBytes = esObj[field] as Uint8Array
        let preference = sendablePreferences.getPreferencesSync(context, { name: field })
        this.configPreferences.set(field, preference)
        this.readConfig(field, nameBytes, preference)
      }
      let selected = this.preferences!.getSync("selected", "").toString()
      AppManager.easytier.selected =
        (selected.length > 0 && this.configPreferences.has(selected)) ? selected : undefined
      Logger.debug("read selected:" + selected + " set:" + AppManager.easytier.selected, this)
      let favorite = this.preferences!.getSync("favorite", "").toString()
      AppManager.data.favorite =
        (favorite.length > 0 && this.configPreferences.has(favorite)) ? favorite : undefined
      Logger.debug("read favorite:" + favorite + " set:" + AppManager.data.favorite, this)
    })
    this.globalConfigs = preferences.getPreferencesSync(context, { name: 'EasyTierGlobalConfigs' })
    this.globalConfigs.getAll((err, obj) => {
      if (err) {
        Logger.error(JSON.stringify(err), this)
        return
      }
      for (const field of Object.keys(obj)) {
        let esObj: ESObject = obj
        let value: string[] = esObj[field]
        Logger.debug("read globalConfigs: " + field + ", length: " + value.length, this)
        AppManager.data.initDataSource(field, value)
      }
    })
    this.black_list_preference = preferences.getPreferencesSync(context, { name: 'EasyTierBlackListApp' })
    this.updateBlackListApps()
    try {
      this.show_log = this.preferences.getSync("show_log", false).valueOf() as boolean
      this.vpn_routes = this.preferences.getSync("vpn_routes", false).valueOf() as boolean
      this.dev = this.preferences.getSync("dev", false).valueOf() as boolean
      this.dns = this.preferences.getSync("dns", false).valueOf() as string
      this.noOldData = this.preferences.getSync("noOldData", false).valueOf() as boolean
      this.holding_detector = this.preferences.getSync("holding_detector", false).valueOf() as boolean
      this.raw_comp_sequence = this.preferences.getSync("raw_comp_sequence", defaultSequence).valueOf() as string
      AppManager.layout.initSequence(this.raw_comp_sequence)
    } catch (error) {
      Logger.error(`PreferenceUtil failed to init.\n${error}`, this)
    }
    if (this.show_log) {
      this.inittedLog = true
      easytier.initTracingSubscriber()
    }
    this.isInit = false
  }

  updateSequence(sequence: string) {
    if (this.preferences !== undefined) {
      try {
        Logger.debug("update raw_comp_sequence:" + sequence, this)
        this.preferences.putSync("raw_comp_sequence", sequence)
        this.preferences.flushSync()
      } catch (error) {
        Logger.error(`PreferenceUtil failed to change raw_comp_sequence.\n${error}`, this)
      }
    }
  }

  @Monitor("show_log", "vpn_routes", "dev", "dns", "noOldData", "holding_detector")
  onChange(monitor: IMonitor) {
    monitor.dirty.forEach((path: string) => {
      if (this.preferences !== undefined && !this.isInit) {
        try {
          Logger.debug("update:" + path + "," + monitor.value(path)?.now, this)
          this.preferences.putSync(path, monitor.value(path)?.now as ValueType)
          this.preferences.flushSync()
        } catch (error) {
          Logger.error(`PreferenceUtil failed to change ${path}.\n${error}`, this)
        }
      }
    })
  }

  addConfig(uuid: string, name: string, config: NetworkConfig) {
    try {
      this.configIDPreferences?.putSync(uuid, new Uint8Array(buffer.from(name, 'utf-8').buffer))
      this.configIDPreferences?.flushSync()
      let preference = sendablePreferences.getPreferencesSync(AppManager.content.context!, { name: uuid })
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
      Logger.error(JSON.stringify(error), this)
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
    const task: taskpool.Task = new taskpool.Task(readConfigFromPreference, field as String, preference);
    return taskpool.execute(task).then((value: object) => {
      let config = value.toString()
      AppManager.data.readConfig(field, name as string, JSON.parse(config) as NetworkConfig)
    }).catch((err: BusinessError) => {
      Logger.error("taskpool error: " + JSON.stringify(err), this)
    })
  }

  getAppInfo(pkgName: string): AppInfo | undefined {
    return this.black_list_apps.get(pkgName)
	}

  setAppInfo(pkgName: string, name: string, icon: string) {
    let info = new AppInfo(pkgName, name, icon)
    this.black_list_preference!.putSync(pkgName, info)
    this.black_list_preference!.flushSync()
    if (!this.black_list_apps.has(pkgName)) {
      this.black_list_apps.set(pkgName, info)
    }else {
      this.black_list_apps.get(pkgName)!.name = name
      this.black_list_apps.get(pkgName)!.icon = icon
    }
  }

  private updateBlackListApps() {
    let obj: ESObject = this.black_list_preference!.getAllSync()
    for (const pkgName of Object.keys(obj)) {
      let info = obj[pkgName] as AppInfo
      this.black_list_apps.set(pkgName, info)
    }
  }

  delAppInfo(pkgName: string) {
    this.black_list_preference!.deleteSync(pkgName)
    this.black_list_preference!.flushSync()
    this.black_list_apps.delete(pkgName)
  }

  updateAppInfo(info: AppInfo) {
    this.black_list_preference!.putSync(info.pkgName, info)
    this.black_list_preference!.flushSync()
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
}