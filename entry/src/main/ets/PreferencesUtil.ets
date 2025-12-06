import { preferences, ValueType } from "@kit.ArkData";
import easytier from "easytier-ohrs"
import { AppManager } from "./AppManager";
import { NetworkConfig } from "./protobuf/api_manage";
import { Logger, LogLocate } from "./util/Logger";
import { buffer, util } from "@kit.ArkTS";

const defaultSequence = 'Instances_0_0_1_1|Favorite_1_0_1_1|Logs_0_1_1_1|SharedPeers_1_1_1_2|QQ_0_2_1_1'

@LogLocate("PreferenceUtil")
@ObservedV2
export class PreferenceUtil {
  @Trace configPreferences: Map<string, preferences.Preferences> = new Map()
  @Trace configIDPreferences: preferences.Preferences | undefined
  @Trace preferences: preferences.Preferences | undefined
  @Trace show_log: boolean = false
  @Trace raw_comp_sequence: string = defaultSequence
  @Trace vpn_routes: boolean = false
  @Trace dev: boolean = false
  @Trace dns: string = ""
  inittedLog: boolean = false
  isInit: boolean = true
  init(preference: preferences.Preferences) {
    this.preferences = preference
    this.configIDPreferences = preferences.getPreferencesSync(AppManager.content.context, { name: 'EasyTierConfigIDs' })
    this.configIDPreferences.getAll((err, obj) => {
      if (err) {
        Logger.error(JSON.stringify(err), this)
        return
      }
      for (const field of Object.keys(obj)) {
        let esObj: ESObject = obj
        try {
          preferences.getPreferences(AppManager.content.context, { name: field }, (err, data) => {
            if (err) {
              Logger.error(JSON.stringify(err), this)
              return
            }
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
            AppManager.data.readConfig(field, name as string, data.getAllSync() as NetworkConfig)
          })
        } catch (_) {}
      }
    })
    try {
      this.show_log = this.preferences.getSync("show_log", false).valueOf() as boolean
      this.vpn_routes = this.preferences.getSync("vpn_routes", false).valueOf() as boolean
      this.dev = this.preferences.getSync("dev", false).valueOf() as boolean
      this.dns = this.preferences.getSync("dns", false).valueOf() as string
      let selected = this.preferences.getSync("selected", "").toString()
      AppManager.easytier.selected = (selected.length > 0 && AppManager.data.configUUIDMap.has(selected))?selected:undefined
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
        Logger.debug("update raw_comp_sequence:"+sequence, this)
        this.preferences.putSync("raw_comp_sequence", sequence)
        this.preferences.flushSync()
      } catch (error) {
        Logger.error(`PreferenceUtil failed to change raw_comp_sequence.\n${error}`, this)
      }
    }
  }
  @Monitor("show_log","vpn_routes", "dev", "dns")
  onChange(monitor: IMonitor) {
    monitor.dirty.forEach((path: string) => {
      if (this.preferences !== undefined && !this.isInit) {
        try {
          Logger.debug("update:"+path+","+monitor.value(path)?.now, this)
          this.preferences.putSync(path, monitor.value(path)?.now as ValueType)
          this.preferences.flushSync()
        } catch (error) {
          Logger.error(`PreferenceUtil failed to change ${path}.\n${error}`, this)
        }
      }
    })
  }

  addConfig(uuid:string, name: string, config: NetworkConfig) {
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