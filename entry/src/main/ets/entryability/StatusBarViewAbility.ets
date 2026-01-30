import { StatusBarViewExtensionAbility } from '@kit.DeskTopExtensionKit';
import { UIExtensionContentSession, Want } from '@kit.AbilityKit';
import { Logger, LogLocate } from '../util/Logger';
import { AppManager } from '../AppManager';

@LogLocate("StatusBarViewAbility")
export default class StatusBarViewAbility extends StatusBarViewExtensionAbility {
  onCreate() {
    Logger.debug("onCreate", this)
    AppManager.preference.init(this.context)
  }

  onSessionCreate(want: Want, session: UIExtensionContentSession) {
    try {
      session.loadContent("pages/StatusBarPage")
    } catch (error) {
      Logger.error(`loadContent failed: ${JSON.stringify(error)}`, this)
    }
  }

  onForeground() {
  }

  onBackground() {
  }

  onSessionDestroy(session: UIExtensionContentSession) {
  }

  onDestroy() {
  }
}
