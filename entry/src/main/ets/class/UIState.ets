import { ValueType } from '@kit.ArkData';
import { AppManager } from '../AppManager';
import { Logger, LogLocate } from '../util/Logger';

@LogLocate("UIState")
@ObservedV2
export class UIState {
  isStatusBar: boolean = false
  @Trace favorite: string | undefined
  @Trace selected: string | undefined
  @Trace editingInstance: string | undefined
  @Trace configUUIDNameMap: Map<string, string> = new Map

  init() {

  }

  @Monitor("favorite")
  onFavoriteChange(monitor: IMonitor) {
    monitor.dirty.forEach((path: string) => {
      if (AppManager.preference.preferences !== undefined && !AppManager.preference.isInit) {
        try {
          if (monitor.value(path)?.now) {
            AppManager.preference.preferences.putSync(path, monitor.value(path)?.now as ValueType)
          } else {
            AppManager.preference.preferences.putSync(path, "" as ValueType)
          }
          AppManager.preference.preferences.flushSync()
        } catch (error) {
          Logger.error(`PreferenceUtil failed to change ${path}.\n${error}`, this)
        }
      }
    })
  }

  @Monitor("selected")
  onSelectedChange(monitor: IMonitor) {
    monitor.dirty.forEach((path: string) => {
      if (AppManager.preference.preferences !== undefined && !AppManager.preference.isInit) {
        try {
          if (monitor.value(path)?.now) {
            AppManager.preference.preferences.putSync(path, monitor.value(path)?.now as ValueType)
          } else {
            AppManager.preference.preferences.putSync(path, "" as ValueType)
          }
          AppManager.preference.preferences.flushSync()
        } catch (error) {
          Logger.error(`PreferenceUtil failed to change ${path}.\n${error}`, this)
        }
      }
    })
  }

  @Monitor("configUUIDNameMap")
  onConfigsChange() {

  }
}