import { preferences, ValueType } from "@kit.ArkData";
import easytier from "easytier-ohrs"
import { Logger, LogLocate } from "./util/Logger";

@LogLocate("PreferenceUtil")
@ObservedV2
export class PreferenceUtil {
  @Trace public static preferences: preferences.Preferences | undefined
  @Trace public static show_log: boolean = false
  @Monitor("preferences")
  onInit() {
    if (PreferenceUtil.preferences !== undefined) {
      try {
        PreferenceUtil.show_log = PreferenceUtil.preferences.getSync("show_log", false).valueOf() as boolean
      } catch (error) {
        Logger.error(`PreferenceUtil failed to init.\n${error}`, PreferenceUtil)
      }
      if (PreferenceUtil.show_log) {
        easytier.hilogGlobalOptions(0, "fhl")
        easytier.initTracingSubscriber()
      }
    }
  }
  @Monitor("show_log")
  onChange(monitor: IMonitor) {
    monitor.dirty.forEach((path: string) => {
      if (PreferenceUtil.preferences !== undefined) {
        try {
          PreferenceUtil.preferences.putSync(path, monitor.value(path)?.now as ValueType)
        } catch (error) {
          Logger.error(`PreferenceUtil failed to change ${path}.\n${error}`, PreferenceUtil)
        }
      }
    })
  }
}