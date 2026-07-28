import { common } from '@kit.AbilityKit'
import { UIContext } from '@kit.ArkUI'
import { AppManager } from '../../AppManager'
import { Logger } from '../../shared/logging/Logger'
import { sendToast } from '../../ToastUtil'

export const EASYTIER_PRO_APPGALLERY_URL: string = 'https://appgallery.huawei.com/apptest/6aN39FB2zKm'

const PROMOTION_PRESENTED_KEY: string = 'easytier_pro_recommendation_presented'

class EasyTierProPromotionServiceClass {
  consumeFirstPresentation(): boolean {
    const store = AppManager.preference.preferences
    if (!store) {
      return false
    }
    try {
      const presented = store.getSync(PROMOTION_PRESENTED_KEY, false).valueOf() as boolean
      if (presented) {
        return false
      }
      store.putSync(PROMOTION_PRESENTED_KEY, true)
      store.flushSync()
      Logger.info('present EasyTier Pro recommendation', 'EasyTierProPromotionService')
      return true
    } catch (error) {
      Logger.error(`persist EasyTier Pro recommendation failed: ${JSON.stringify(error)}`,
        'EasyTierProPromotionService')
      return false
    }
  }

  openAppGallery(uiContext: UIContext): void {
    const hostContext = uiContext.getHostContext()
    if (!hostContext) {
      sendToast($r('app.string.easytier_pro_open_failed'), $r('sys.symbol.exclamationmark_circle'), 1)
      return
    }
    try {
      const context = hostContext as common.UIAbilityContext
      context.openLink(EASYTIER_PRO_APPGALLERY_URL).catch(() => {
        sendToast($r('app.string.easytier_pro_open_failed'), $r('sys.symbol.exclamationmark_circle'), 1)
      })
    } catch (_) {
      sendToast($r('app.string.easytier_pro_open_failed'), $r('sys.symbol.exclamationmark_circle'), 1)
    }
  }
}

export const EasyTierProPromotionService = new EasyTierProPromotionServiceClass()
