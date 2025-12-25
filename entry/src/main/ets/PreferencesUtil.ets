import { preferences, ValueType } from '@kit.ArkData';
import easytier from 'easytier-ohrs';
import { AppManager } from './AppManager';
import { NetworkConfig } from './protobuf/api_manage';
import { Logger, LogLocate } from './util/Logger';
import { buffer, util } from '@kit.ArkTS';

const defaultSequence = 'Instances_0_0_2_1|Favorite_0_1_1_1|Logs_1_1_1_1|QQ_0_2_1_1|SharedPeers_1_2_1_1'

@LogLocate("PreferenceUtil")
@ObservedV2
export class PreferenceUtil {
  @Trace configPreferences: Map<string, preferences.Preferences> = new Map()
  @Trace configIDPreferences: preferences.Preferences | undefined
  @Trace globalConfigs: preferences.Preferences | undefined
  @Trace preferences: preferences.Preferences | undefined
  @Trace show_log: boolean = false
  @Trace raw_comp_sequence: string = defaultSequence
  @Trace vpn_routes: boolean = false
  @Trace dev: boolean = false
  @Trace dns: string = ""
  @Trace noOldData: boolean = false
  @Trace holding_detector: boolean = false
  inittedLog: boolean = false
  isInit: boolean = true

  init(preference: preferences.Preferences) {
    this.preferences = preference
    this.configIDPreferences = preferences.getPreferencesSync(AppManager.content.context, { name: 'EasyTierConfigIDs' })
    this.configIDPreferences.getAll(async (err, obj) => {
      if (err) {
        Logger.error(JSON.stringify(err), this)
        return
      }
      for (const field of Object.keys(obj)) {
        let esObj: ESObject = obj
        try {
          let data = preferences.getPreferencesSync(AppManager.content.context, { name: field })
          let textDecoderOptions: util.TextDecoderOptions = {
            fatal: false,
            ignoreBOM: true
          }
          let decodeToStringOptions: util.DecodeToStringOptions = {
            stream: false
          }
          let textDecoder = util.TextDecoder.create('utf-8', textDecoderOptions);
          let name = textDecoder.decodeToString(esObj[field] as Uint8Array, decodeToStringOptions);
          this.configPreferences.set(field, data)
          let config = data.getAllSync() as NetworkConfig
          Logger.debug("read config: " + JSON.stringify(config, null, 2), this)
          AppManager.data.readConfig(field, name as string, config)
        } catch (_) {}
      }
      let selected = this.preferences!.getSync("selected", "").toString()
      AppManager.easytier.selected =
        (selected.length > 0 && AppManager.data.configUUIDMap.has(selected)) ? selected : undefined
      Logger.debug("read selected:" + selected+" set:"+AppManager.easytier.selected, this)
      let favorite = this.preferences!.getSync("favorite", "").toString()
      AppManager.data.favorite =
        (favorite.length > 0 && AppManager.data.configUUIDMap.has(favorite)) ? favorite : undefined
      Logger.debug("read favorite:" + favorite+" set:"+AppManager.data.favorite, this)
    })
    this.globalConfigs = preferences.getPreferencesSync(AppManager.content.context, { name: 'EasyTierGlobalConfigs' })
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

  @Monitor("show_log","vpn_routes","dev","dns","noOldData","holding_detector")
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
      let preference = preferences.getPreferencesSync(AppManager.content.context, { name: uuid })
      Object.entries(config).forEach((value: [string, preferences.ValueType | undefined]) => {
        if (value[1]) {
          preference.putSync(value[0], value[1])
        }
      })
      preference.flushSync()
      this.configPreferences.set(uuid, preference)
    } catch (error) {
      Logger.error(JSON.stringify(error), this)
    }
  }
}