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
  const quote = await IapService.queryPrice(context)
  let priceText = ''
  if (quote.promotional) {
    priceText = `\n促销价：${quote.price}\n原价：${quote.originalPrice}`
  } else if (quote.price.length > 0) {
    priceText = `\n价格：${quote.price}`
  }
  try {
    const result = await uiContext.getPromptAction().showDialog({
      title: '解锁跨设备控制',
      message: `跨设备控制为增值功能，解锁后可查看其他设备状态、一次性下发本机配置并启停受控实例。\n\n本功能依赖鸿蒙软总线，仅能控制一定范围内同账号的鸿蒙设备，请慎重购买。${priceText}`,
      buttons: [
        { text: quote.price.length > 0 ? `购买 ${quote.price}` : '立即购买', color: '#0A59F7' },
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
  if (gateBusy) {
    return
  }
  gateBusy = true
  const context = uiContext.getHostContext() as common.UIAbilityContext
  IapService.refreshEntitlementForGate(context).then((owned: boolean) => {
    if (owned || IapService.isRemoteControlUnlocked()) {
      pushRemoteControlPage(beforePush)
      return
    }
    return showPaywall(uiContext, context, beforePush)
  }).catch(() => {
  }).finally(() => {
    gateBusy = false
  })
}
