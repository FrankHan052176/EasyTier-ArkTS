import { preferences, ValueType } from "@kit.ArkData";
import easytier from "easytier-ohrs"
import { AppManager } from "./AppManager";
import { CompSizeWithPos } from "./LayoutUtil";
import { Logger, LogLocate } from "./util/Logger";
import { ConfigurationConstant } from "@kit.AbilityKit";

const defaultSequence = 'Instances_0_0_1_1|Favorite_1_0_1_1|Logs_0_1_1_1|SharedPeers_1_1_1_2|QQ_0_2_1_1'

@LogLocate("PreferenceUtil")
@ObservedV2
export class PreferenceUtil {
  @Trace preferences: preferences.Preferences | undefined
  @Trace show_log: boolean = false
  @Trace raw_comp_sequence: string = defaultSequence
  @Trace color_mode:ConfigurationConstant.ColorMode = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT
  isInit: boolean = true
  init(preferences: preferences.Preferences) {
    this.preferences = preferences
    try {
      this.show_log = this.preferences.getSync("show_log", false).valueOf() as boolean
      this.raw_comp_sequence = this.preferences.getSync("raw_comp_sequence", defaultSequence).valueOf() as string
      AppManager.layout.initSequence(this.raw_comp_sequence)
    } catch (error) {
      Logger.error(`PreferenceUtil failed to init.\n${error}`, PreferenceUtil)
    }
    if (this.show_log) {
      easytier.initTracingSubscriber()
    }
    this.isInit = false
  }
  updateSequence(sequence: string) {
    if (this.preferences !== undefined) {
      try {
        this.preferences.putSync("raw_comp_sequence", sequence)
        this.preferences.flushSync()
      } catch (error) {
        Logger.error(`PreferenceUtil failed to change raw_comp_sequence.\n${error}`, PreferenceUtil)
      }
    }
  }
  @Monitor("show_log")
  onChange(monitor: IMonitor) {
    monitor.dirty.forEach((path: string) => {
      if (this.preferences !== undefined && !this.isInit) {
        try {
          Logger.debug("update:"+path+","+monitor.value(path)?.before)
          this.preferences.putSync(path, monitor.value(path)?.now as ValueType)
          this.preferences.flushSync()
        } catch (error) {
          Logger.error(`PreferenceUtil failed to change ${path}.\n${error}`, PreferenceUtil)
        }
      }
    })
  }
}