import { UIContext } from '@kit.ArkUI'
import { common } from '@kit.AbilityKit'
import { HMRouterMgr } from '@hadss/hmrouter'
import { IapService } from './IapService'
import { sendToast } from '../../ToastUtil'

let gateBusy: boolean = false

function pushRemoteControlPage(beforePush?: () => void): void {
  if (beforePush) {
    beforePush()
  }
  HMRouterMgr.push({ pageUrl: 'RemoteControlPage' })
}

async function showPaywall(uiContext: UIContext, context: common.UIAbilityContext,
  beforePush?: () => void): Promise<void> {
  const price = await IapService.queryPrice(context)
  const priceText = price.length > 0 ? `\n价格：${price}` : ''
  try {
    const result = await uiContext.getPromptAction().showDialog({
      title: '解锁跨设备控制',
      message: `跨设备控制为增值功能，解锁后可远程查看、编辑并启停其他设备上的 EasyTier 实例。${priceText}`,
      buttons: [
        { text: price.length > 0 ? `购买 ${price}` : '立即购买', color: '#0A59F7' },
        { text: '恢复购买', color: '#0A59F7' },
        { text: '取消', color: '#99182431' }
      ]
    })
    if (result.index === 0) {
      const owned = await IapService.purchaseRemoteControl(context)
      if (owned) {
        pushRemoteControlPage(beforePush)
      }
    } else if (result.index === 1) {
      const owned = await IapService.refreshEntitlement(context, true)
      if (owned) {
        sendToast('已恢复购买权益', $r('sys.symbol.checkmark_circle'), 0)
        pushRemoteControlPage(beforePush)
      } else {
        sendToast('未找到已购记录', $r('sys.symbol.exclamationmark_circle'), 1)
      }
    }
  } catch (_) {
    // 对话框被外部关闭
  }
}

/**
 * 跨设备控制统一入口：主页卡片与设置页共用同一套权益校验与付费引导，
 * 已解锁直接进入，未解锁弹出购买/恢复购买对话框。
 */
export function openRemoteControlGated(uiContext: UIContext, beforePush?: () => void): void {
  if (IapService.isRemoteControlUnlocked()) {
    pushRemoteControlPage(beforePush)
    return
  }
  if (gateBusy) {
    return
  }
  gateBusy = true
  const context = uiContext.getHostContext() as common.UIAbilityContext
  IapService.ensureEntitlementLoaded(context).then((owned: boolean) => {
    if (owned) {
      pushRemoteControlPage(beforePush)
      return
    }
    return showPaywall(uiContext, context, beforePush)
  }).catch(() => {
  }).finally(() => {
    gateBusy = false
  })
}
