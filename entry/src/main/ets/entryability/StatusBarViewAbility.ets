import { StatusBarViewExtensionAbility } from '@kit.DeskTopExtensionKit';
import { UIExtensionContentSession, Want } from '@kit.AbilityKit';
import { Logger, LogLocate } from '../util/Logger';

@LogLocate("StatusBarViewAbility")
export default class StatusBarViewAbility extends StatusBarViewExtensionAbility {
  onCreate() {
    Logger.debug("onCreate", this)
  }

  onSessionCreate(want: Want, session: UIExtensionContentSession) {
    try {
      session.loadContent("pages/StatusBarPage")
    } catch (error) {
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