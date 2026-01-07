import { StatusBarViewExtensionAbility } from '@kit.DeskTopExtensionKit';
import { UIExtensionContentSession, Want } from '@kit.AbilityKit';
import { Logger, LogLocate } from '../util/Logger';
import { EventHelper } from '../util/EventHelper';

@LogLocate("StatusBarViewAbility")
export default class StatusBarViewAbility extends StatusBarViewExtensionAbility {
  onCreate() {
    EventHelper.commonPublish("amazing")
    Logger.debug("onCreate", this)
  }

  onSessionCreate(want: Want, session: UIExtensionContentSession) {
    try {
      session.loadContent("pages/StatusBarPage")
    } catch (error) {}
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