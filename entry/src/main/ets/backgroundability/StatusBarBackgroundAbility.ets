import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit'
import { commonEventManager, BusinessError } from '@kit.BasicServicesKit'
import { Logger, LogLocate } from '../shared/logging/Logger'
import { STATUS_BAR_BACKGROUND_TERMINATE_EVENT } from '../services/runtime/AbilityRuntimePolicy'

@LogLocate('StatusBarBackgroundAbility')
export default class StatusBarBackgroundAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    Logger.info(`status bar background created reason=${launchParam.launchReason}`, this)
  }

  onPrepareToTerminate(): boolean {
    commonEventManager.publish(STATUS_BAR_BACKGROUND_TERMINATE_EVENT, (err: BusinessError) => {
      if (err) {
        Logger.error(`publish status bar terminate event failed: ${err.code}, ${err.message}`, this)
        return
      }
      Logger.info('status bar terminate event published', this)
    })
    return false
  }

  onDestroy(): void {
    Logger.info('status bar background destroyed', this)
  }
}
