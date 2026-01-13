import { AppManager, Spx2vp } from './AppManager'
import { Logger, LogLocate } from './util/Logger'
import { ConfigurationConstant } from '@kit.AbilityKit'

export enum UIType {
  Column_1 = 2, Column_2 = 4, Column_3 = 6
}

@LogLocate("WindowUtil")
@ObservedV2
export class WindowUtil {
  public static statusBarHeight: number = 0
  public static navigationBarHeight: number = 0
  @Trace public static width: number = 0
  @Trace public static height: number = 0
  @Trace public static uiType: UIType = UIType.Column_1
  @Trace public static colorMode: ConfigurationConstant.ColorMode = ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET

  static set setStatusBarHeight(value: number) {
    WindowUtil.statusBarHeight = Spx2vp(value)
  }

  static set setNavigationBarHeight(value: number) {
    WindowUtil.navigationBarHeight = Spx2vp(value)
  }

  public static update(width: number, height: number) {
    animateToImmediately({
      duration: 300,
      curve: Curve.Friction
    }, () => {
      WindowUtil.width = Spx2vp(width)
      WindowUtil.height = Spx2vp(height)
      if (WindowUtil.width < 720) {
        WindowUtil.uiType = UIType.Column_1
      } else if (WindowUtil.width >= 1080) {
        WindowUtil.uiType = UIType.Column_3
      } else {
        WindowUtil.uiType = UIType.Column_2
      }
    })
    Logger.debug(`WindowUtil update.`, WindowUtil)
  }

  public static foreground() {

  }

  public static background() {

  }

  public static windowStageDestroy() {

  }
}