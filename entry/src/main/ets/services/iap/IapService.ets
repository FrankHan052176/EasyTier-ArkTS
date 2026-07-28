import { common } from '@kit.AbilityKit'
import { iap } from '@kit.IAPKit'
import { BusinessError } from '@kit.BasicServicesKit'
import BuildProfile from 'BuildProfile'
import { AppManager } from '../../AppManager'
import { Logger, LogLocate } from '../../shared/logging/Logger'
import { sendToast } from '../../ToastUtil'
import { PurchaseOrderPayload, VerifiedPurchase, verifyCachedPurchaseJws, verifyPurchaseData } from './IapReceiptVerifier'

/** 跨设备控制解锁商品（应用内非消耗型商品，须在 AGC 后台配置同名商品） */
export const REMOTE_CONTROL_PRODUCT_ID = 'remote_control'
const IAP_RECEIPT_PREF_KEY = 'iap_remote_control_verified_receipt'
const LEGACY_IAP_OWNED_PREF_KEY = 'iap_remote_control_owned'

/**
 * IAP 权益服务：
 * - 权益判定以 queryPurchases(NONCONSUMABLE, CURRENT_ENTITLEMENT) 为准；
 * - 每次校验前补确认 UNFINISHED 订单（掉单恢复）；
 * - 仅信任通过华为证书链、ES256 签名及业务字段校验的订单；
 * - 联网失败时仅回退到本地保存的已验签 JWS（下次联网自动纠正）。
 */
@LogLocate('IapService')
@ObservedV2
export class IapServiceClass {
  @Trace remoteControlOwned: boolean = false
  @Trace checking: boolean = false
  @Trace price: string = ''
  private entitlementLoaded: boolean = false
  private cachedReceiptLoaded: boolean = false
  private cachedReceipt: string = ''

  /** debug 便于功能联调直接放行；release 仍只信任已验签的已购权益。 */
  isRemoteControlUnlocked(): boolean {
    return BuildProfile.DEBUG || this.remoteControlOwned
  }

  private loadCachedReceipt(): string {
    if (this.cachedReceiptLoaded) {
      return this.cachedReceipt
    }
    this.cachedReceiptLoaded = true
    try {
      this.cachedReceipt = AppManager.preference.preferences?.getSync(IAP_RECEIPT_PREF_KEY, '').toString() ?? ''
    } catch (_) {
      this.cachedReceipt = ''
    }
    return this.cachedReceipt
  }

  private persistVerifiedEntitlement(receipt: string): void {
    this.cachedReceiptLoaded = true
    this.cachedReceipt = receipt
    this.remoteControlOwned = true
    try {
      AppManager.preference.preferences?.putSync(IAP_RECEIPT_PREF_KEY, receipt)
      AppManager.preference.preferences?.deleteSync(LEGACY_IAP_OWNED_PREF_KEY)
      AppManager.preference.preferences?.flushSync()
    } catch (_) {
    }
  }

  private clearEntitlement(): void {
    this.cachedReceiptLoaded = true
    this.cachedReceipt = ''
    this.remoteControlOwned = false
    try {
      AppManager.preference.preferences?.deleteSync(IAP_RECEIPT_PREF_KEY)
      AppManager.preference.preferences?.deleteSync(LEGACY_IAP_OWNED_PREF_KEY)
      AppManager.preference.preferences?.flushSync()
    } catch (_) {
    }
  }

  private async restoreVerifiedCache(): Promise<boolean> {
    const receipt = this.loadCachedReceipt()
    if (receipt.length === 0) {
      this.remoteControlOwned = false
      return false
    }
    try {
      await verifyCachedPurchaseJws(receipt)
      this.remoteControlOwned = true
      return true
    } catch (error) {
      Logger.error(`cached IAP receipt rejected: ${(error as Error).message}`, this)
      this.clearEntitlement()
      return false
    }
  }

  private async verifiedRemotePurchase(purchaseDataList: string[]): Promise<VerifiedPurchase | undefined> {
    for (const purchaseData of purchaseDataList) {
      try {
        return await verifyPurchaseData(purchaseData)
      } catch (error) {
        Logger.error(`IAP receipt rejected: ${(error as Error).message}`, this)
      }
    }
    return undefined
  }

  private async finishPurchase(context: common.UIAbilityContext, purchase: VerifiedPurchase): Promise<void> {
    const payload = purchase.payload
    if (!payload.purchaseToken || !payload.purchaseOrderId) {
      return
    }
    try {
      await iap.finishPurchase(context, {
        productType: iap.ProductType.NONCONSUMABLE,
        purchaseToken: payload.purchaseToken,
        purchaseOrderId: payload.purchaseOrderId
      })
    } catch (error) {
      const err = error as BusinessError
      if (err.code !== iap.IAPErrorCode.PURCHASE_FINISHED) {
        throw new Error(`finishPurchase failed: ${err.code} ${err.message}`)
      }
    }
  }

  /** 先发放已验签权益，再补确认未完成订单；确认失败留待下次重试。 */
  private async finishUnfinishedOrders(context: common.UIAbilityContext): Promise<VerifiedPurchase | undefined> {
    const result = await iap.queryPurchases(context, {
      productType: iap.ProductType.NONCONSUMABLE,
      queryType: iap.PurchaseQueryType.UNFINISHED
    })
    const purchase = await this.verifiedRemotePurchase(result.purchaseDataList ?? [])
    if (purchase === undefined) {
      return undefined
    }
    this.persistVerifiedEntitlement(purchase.jwsPurchaseOrder)
    try {
      await this.finishPurchase(context, purchase)
      Logger.info('finished pending purchase order', this)
    } catch (error) {
      const err = error as BusinessError
      Logger.error(`finishPurchase failed: ${err.code} ${err.message}`, this)
    }
    return purchase
  }

  private showPurchaseError(error: BusinessError): void {
    let message = '购买失败，请稍后重试'
    if (error.code === iap.IAPErrorCode.ACCOUNT_NOT_LOGGED_IN) {
      message = '请先登录华为账号'
    } else if (error.code === iap.IAPErrorCode.INVALID_PRODUCT) {
      message = '商品暂不可用，请检查应用市场配置'
    } else if (error.code === iap.IAPErrorCode.APP_NOT_AUTHORIZED) {
      message = '当前版本未开通应用内支付'
    } else if (error.code === iap.IAPErrorCode.PRODUCT_TERRITORY_NOT_SUPPORTED ||
      error.code === iap.IAPErrorCode.ACCOUNT_TERRITORY_NOT_SUPPORTED) {
      message = '当前账号所在地区暂不支持购买'
    } else if (error.code === iap.IAPErrorCode.NETWORK_ERROR) {
      message = '网络连接失败，请稍后重试'
    } else if (error.code === iap.IAPErrorCode.ACCOUNT_NOT_TEST || error.code === iap.IAPErrorCode.APP_NOT_DEBUG) {
      message = '调试支付账号或应用版本不符合沙箱要求'
    } else if (error.code === iap.IAPErrorCode.INVALID_PURCHASE_SIGNATURE) {
      message = '购买结果校验失败，未解锁功能'
    }
    sendToast(message, $r('sys.symbol.exclamationmark_circle'), 1)
  }

  private async refreshAfterPurchaseFailure(context: common.UIAbilityContext, error: BusinessError): Promise<boolean> {
    if (error.code === iap.IAPErrorCode.PRODUCT_OWNED || error.code === iap.IAPErrorCode.SYSTEM_ERROR) {
      const owned = await this.refreshEntitlement(context)
      if (owned) {
        sendToast('已恢复购买权益', $r('sys.symbol.checkmark_circle'), 0)
      }
      return owned
    }
    if (error.code !== iap.IAPErrorCode.USER_CANCELED) {
      this.showPurchaseError(error)
    }
    return false
  }

  /** 联网刷新权益；失败时返回本地缓存值 */
  async refreshEntitlement(context: common.UIAbilityContext, interactive: boolean = false): Promise<boolean> {
    this.loadCachedReceipt()
    this.checking = true
    try {
      await iap.queryEnvironmentStatus(context)
      const unfinished = await this.finishUnfinishedOrders(context)
      const result = await iap.queryPurchases(context, {
        productType: iap.ProductType.NONCONSUMABLE,
        queryType: iap.PurchaseQueryType.CURRENT_ENTITLEMENT
      })
      const current = await this.verifiedRemotePurchase(result.purchaseDataList ?? [])
      const ownedPurchase = current ?? unfinished
      if (ownedPurchase !== undefined) {
        this.persistVerifiedEntitlement(ownedPurchase.jwsPurchaseOrder)
      } else {
        this.clearEntitlement()
      }
      this.entitlementLoaded = true
      return ownedPurchase !== undefined
    } catch (error) {
      const err = error as BusinessError
      Logger.error(`refreshEntitlement failed: ${err.code} ${err.message}`, this)
      if (interactive) {
        sendToast('无法连接应用市场，请确认已登录华为账号', $r('sys.symbol.exclamationmark_circle'), 1)
      }
      const restored = this.remoteControlOwned || await this.restoreVerifiedCache()
      this.entitlementLoaded = restored
      return restored
    } finally {
      this.checking = false
    }
  }

  /** 首次访问入口时的权益判定（带缓存） */
  async ensureEntitlementLoaded(context: common.UIAbilityContext): Promise<boolean> {
    if (this.entitlementLoaded) {
      return this.remoteControlOwned
    }
    return this.refreshEntitlement(context)
  }

  /** 查询商品展示价（含货币符号） */
  async queryPrice(context: common.UIAbilityContext): Promise<string> {
    try {
      const products = await iap.queryProducts(context, {
        productType: iap.ProductType.NONCONSUMABLE,
        productIds: [REMOTE_CONTROL_PRODUCT_ID]
      })
      if (products.length > 0) {
        this.price = products[0].localPrice ?? ''
      }
    } catch (error) {
      const err = error as BusinessError
      Logger.error(`queryProducts failed: ${err.code} ${err.message}`, this)
    }
    return this.price
  }

  /** 发起购买，返回是否已获得权益 */
  async purchaseRemoteControl(context: common.UIAbilityContext): Promise<boolean> {
    this.loadCachedReceipt()
    try {
      await iap.queryEnvironmentStatus(context)
      const result = await iap.createPurchase(context, {
        productId: REMOTE_CONTROL_PRODUCT_ID,
        productType: iap.ProductType.NONCONSUMABLE
      })
      const purchase = await verifyPurchaseData(result.purchaseData)
      // 发放权益必须发生在 finishPurchase 之前，避免确认成功后本地发放失败。
      this.persistVerifiedEntitlement(purchase.jwsPurchaseOrder)
      this.entitlementLoaded = true
      try {
        await this.finishPurchase(context, purchase)
      } catch (error) {
        const err = error as BusinessError
        Logger.error(`finishPurchase after create failed: ${err.code} ${err.message}`, this)
      }
      sendToast('已解锁跨设备控制', $r('sys.symbol.checkmark_circle'), 0)
      return true
    } catch (error) {
      const err = error as BusinessError
      Logger.error(`createPurchase failed: ${err.code} ${err.message}`, this)
      return this.refreshAfterPurchaseFailure(context, err)
    }
  }
}

export const IapService = new IapServiceClass()
