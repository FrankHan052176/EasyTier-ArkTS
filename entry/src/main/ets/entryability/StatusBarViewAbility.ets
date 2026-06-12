import { StatusBarViewExtensionAbility } from '@kit.StatusBarExtensionKit';
import { UIExtensionContentSession, Want } from '@kit.AbilityKit';
import { Logger, LogLocate } from '../shared/logging/Logger';
import { AppManager } from '../AppManager';

@LogLocate("StatusBarViewAbility")
export default class StatusBarViewAbility extends StatusBarViewExtensionAbility {
  onCreate() {
    Logger.debug("onCreate", this)
    AppManager.preference.init(this.context).catch((error: Error) => {
      Logger.error(`PreferenceUtil failed to init: ${JSON.stringify(error)}`, this)
    })
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
