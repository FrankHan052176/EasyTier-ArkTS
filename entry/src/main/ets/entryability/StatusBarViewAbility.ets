import { StatusBarViewExtensionAbility } from '@kit.DeskTopExtensionKit';
import { UIExtensionContentSession, Want } from '@kit.AbilityKit';
import { Logger } from '../util/Logger';

export default class StatusBarViewAbility extends StatusBarViewExtensionAbility {
  onCreate() {
    Logger.debug("oncreate", "StatusBarViewAbility")
  }

  onSessionCreate(want: Want, session: UIExtensionContentSession) {
    session.loadContent("pages/StatusBarPage")
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