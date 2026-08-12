import { common } from '@kit.AbilityKit'
import { cloudFunction } from '@kit.CloudFoundationKit'
import { iap } from '@kit.IAPKit'
import { BusinessError } from '@kit.BasicServicesKit'
import { hilog } from '@kit.PerformanceAnalysisKit'
import BuildProfile from 'BuildProfile'
import { AppManager } from '../../AppManager'
import { Logger, LogLocate } from '../../shared/logging/Logger'
import { sendToast } from '../../ToastUtil'
import { EventHelper } from '../../util/EventHelper'
import { PurchaseOrderPayload, VerifiedPurchase, verifyCachedPurchaseJws, verifyPurchaseData } from './IapReceiptVerifier'

/** 跨设备控制解锁商品（应用内非消耗型商品，须在 AGC 后台配置同名商品） */
export const REMOTE_CONTROL_PRODUCT_ID = 'remote_control'
export const REMOTE_CONTROL_ENTITLEMENT_CHANGED_EVENT = 'remote_control_entitlement_changed'
const IAP_RECEIPT_PREF_KEY = 'iap_remote_control_verified_receipt'
const IAP_PURCHASE_ORDER_ID_PREF_KEY = 'iap_remote_control_purchase_order_id'
const IAP_ENTITLEMENT_VALIDATED_AT_PREF_KEY = 'iap_remote_control_validated_at'
const LEGACY_IAP_OWNED_PREF_KEY = 'iap_remote_control_owned'
const IAP_DEBUG_OVERRIDE_PREF_KEY = 'iap_remote_control_debug_override'
export const IAP_ENTITLEMENT_GATE_CACHE_MS = 5 * 60 * 1000
export const IAP_ENTITLEMENT_OFFLINE_GRACE_MS = 24 * 60 * 60 * 1000
const IAP_DIAGNOSTIC_DOMAIN = 0xFF00
const IAP_DIAGNOSTIC_TAG = 'IAP_PRICE'
const IAP_DIAGNOSTIC_CHUNK_SIZE = 800
const IAP_PROMOTIONAL_JWS_FUNCTION = 'issue-iap-promotional-jws'
const IAP_PROMOTIONAL_JWS_TIMEOUT_MS = 10 * 1000
const IAP_PROMOTIONAL_JWS_INITIAL_RETRY_DELAY_MS = 600
const IAP_PROMOTIONAL_JWS_CLOCK_SKEW_SECONDS = 30
const IAP_PROMOTIONAL_JWS_MAX_LIFETIME_SECONDS = 60 * 60

export type IapDebugEntitlementOverride = 'real' | 'grant' | 'revoke'

export class IapPriceQuote {
  price: string
  originalPrice: string
  promotional: boolean

  constructor(price: string, originalPrice: string, promotional: boolean) {
    this.price = price
    this.originalPrice = originalPrice
    this.promotional = promotional
  }
}

interface IapPromotionalJwsRequest {
  purpose: string
  offerId: string
}

interface IapPromotionalJwsBody {
  ok?: boolean
  code?: string
  offerId?: string
  expiresAt?: number
  jwsRepresentation?: string
}

interface IapPromotionalJwsHttpResponse {
  body?: string | IapPromotionalJwsBody
  statusCode?: string | number
}

export class IapPromotionalJws {
  offerId: string
  expiresAt: number
  jwsRepresentation: string

  constructor(offerId: string, expiresAt: number, jwsRepresentation: string) {
    this.offerId = offerId
    this.expiresAt = expiresAt
    this.jwsRepresentation = jwsRepresentation
  }
}

function isCompactJws(value: string): boolean {
  const parts = value.split('.')
  if (parts.length !== 3) {
    return false
  }
  const base64UrlPart = /^[A-Za-z0-9_-]+$/
  return parts[0].length > 0 && parts[1].length > 0 && parts[2].length > 0 &&
    base64UrlPart.test(parts[0]) && base64UrlPart.test(parts[1]) && base64UrlPart.test(parts[2])
}

function parsePromotionalJwsBody(value: string | Object): IapPromotionalJwsBody {
  if (typeof value === 'string') {
    return JSON.parse(value) as IapPromotionalJwsBody
  }
  return value as IapPromotionalJwsBody
}

export function parseIapPromotionalJwsResult(value: string | Object, expectedOfferId: string,
  nowSeconds: number = Math.floor(Date.now() / 1000)): IapPromotionalJws {
  let body = parsePromotionalJwsBody(value)
  const response = body as IapPromotionalJwsHttpResponse
  if (response.body !== undefined) {
    if (response.statusCode !== undefined) {
      const statusCode = Number.parseInt(response.statusCode.toString())
      if (!Number.isSafeInteger(statusCode) || statusCode < 200 || statusCode >= 300) {
        throw new Error(`优惠签名服务返回状态 ${response.statusCode}`)
      }
    }
    body = parsePromotionalJwsBody(response.body)
  }
  if (body.ok !== true) {
    throw new Error(`优惠签名服务拒绝请求${body.code ? `：${body.code}` : ''}`)
  }
  const offerId = body.offerId?.trim() ?? ''
  if (offerId.length === 0 || offerId !== expectedOfferId) {
    throw new Error('优惠签名与当前优惠不匹配')
  }
  const expiresAt = body.expiresAt ?? 0
  if (!Number.isSafeInteger(expiresAt) || expiresAt <= nowSeconds + IAP_PROMOTIONAL_JWS_CLOCK_SKEW_SECONDS ||
    expiresAt > nowSeconds + IAP_PROMOTIONAL_JWS_MAX_LIFETIME_SECONDS) {
    throw new Error('优惠签名有效期无效')
  }
  const jwsRepresentation = body.jwsRepresentation?.trim() ?? ''
  if (!isCompactJws(jwsRepresentation)) {
    throw new Error('优惠签名格式无效')
  }
  return new IapPromotionalJws(offerId, expiresAt, jwsRepresentation)
}

export function isIapPromotionalJwsInitialTransportError(code: number, message: string): boolean {
  return code === 0 && message.trim().toLowerCase().includes('create http task error')
}

function delay(milliseconds: number): Promise<void> {
  return new Promise<void>((resolve) => {
    setTimeout(resolve, milliseconds)
  })
}

export function isIapDebugEntitlementOverride(value: string): boolean {
  return value === 'real' || value === 'grant' || value === 'revoke'
}

export function isIapPromotionalPrice(microPrice: number, originalMicroPrice: number): boolean {
  return Number.isSafeInteger(microPrice) && microPrice >= 0 &&
    Number.isSafeInteger(originalMicroPrice) && originalMicroPrice > microPrice
}

function logIapProductDiagnostic(product: iap.Product, index: number): void {
  if (!BuildProfile.DEBUG) {
    return
  }
  const offers = product.promotionalOffers ?? []
  hilog.info(IAP_DIAGNOSTIC_DOMAIN, IAP_DIAGNOSTIC_TAG, '%{public}s',
    `product[${index}] id=${product.id} type=${product.type} status=${product.status ?? -1} ` +
      `price=${product.price} localPrice=${product.localPrice ?? ''} microPrice=${product.microPrice} ` +
      `originalLocalPrice=${product.originalLocalPrice} originalMicroPrice=${product.originalMicroPrice} ` +
      `currency=${product.currency} promotionalOffers=${offers.length}`)
  const raw = product.jsonRepresentation ?? ''
  if (raw.length === 0) {
    hilog.info(IAP_DIAGNOSTIC_DOMAIN, IAP_DIAGNOSTIC_TAG, '%{public}s',
      `product[${index}] jsonRepresentation=<empty>`)
    return
  }
  for (let offset = 0; offset < raw.length; offset += IAP_DIAGNOSTIC_CHUNK_SIZE) {
    hilog.info(IAP_DIAGNOSTIC_DOMAIN, IAP_DIAGNOSTIC_TAG, '%{public}s',
      `product[${index}] json[${offset}]=${raw.substring(offset, offset + IAP_DIAGNOSTIC_CHUNK_SIZE)}`)
  }
}

export function applyIapDebugEntitlementOverride(owned: boolean, override: string,
  debug: boolean): boolean {
  if (!debug || override === 'real') {
    return owned
  }
  return override === 'grant'
}

export function isIapEntitlementGateCacheFresh(checkedAt: number, now: number = Date.now()): boolean {
  const age = now - checkedAt
  return Number.isSafeInteger(checkedAt) && checkedAt > 0 && age >= 0 && age <= IAP_ENTITLEMENT_GATE_CACHE_MS
}

export function isIapEntitlementValidationFresh(validatedAt: number, now: number = Date.now()): boolean {
  const age = now - validatedAt
  return Number.isSafeInteger(validatedAt) && validatedAt > 0 && age >= 0 && age <= IAP_ENTITLEMENT_OFFLINE_GRACE_MS
}

/**
 * IAP 权益服务：
 * - 权益判定以 queryPurchases(NONCONSUMABLE, CURRENT_ENTITLEMENT) 为准；
 * - 每次校验前补确认 UNFINISHED 订单（掉单恢复）；
 * - 仅信任通过华为证书链、ES256 签名及业务字段校验的订单；
 * - 联网失败时仅在最近一次在线确认后的 24 小时内回退到本地已验签 JWS。
 */
@LogLocate('IapService')
@ObservedV2
export class IapServiceClass {
  @Trace remoteControlOwned: boolean = false
  @Trace checking: boolean = false
  @Trace price: string = ''
  @Trace originalPrice: string = ''
  @Trace promotionalPrice: boolean = false
  private promotionalOfferId: string = ''
  private entitlementLoaded: boolean = false
  private cachedReceiptLoaded: boolean = false
  private cachedReceipt: string = ''
  private cachedPurchaseOrderIdLoaded: boolean = false
  private cachedPurchaseOrderId: string = ''
  private validatedAtLoaded: boolean = false
  private validatedAt: number = 0
  private refreshInFlight: Promise<boolean> | undefined = undefined
  private refreshFailed: boolean = false
  private lastOnlineEntitlementCheckedAt: number = 0
  private lastOnlineEntitlementOwned: boolean = false
  private debugOverrideLoaded: boolean = false
  private debugOverride: IapDebugEntitlementOverride = 'real'

  /** Debug 与 Release 均以经过校验的当前购买权益为准。 */
  isRemoteControlUnlocked(): boolean {
    return applyIapDebugEntitlementOverride(this.remoteControlOwned, this.loadDebugOverride(), BuildProfile.DEBUG)
  }

  /** Debug 专属本地测试权益覆盖；Release 构建永远拒绝写入或使用该状态。 */
  getDebugEntitlementOverride(): IapDebugEntitlementOverride {
    return this.loadDebugOverride()
  }

  setDebugEntitlementOverride(override: IapDebugEntitlementOverride): void {
    if (!BuildProfile.DEBUG) {
      return
    }
    this.debugOverrideLoaded = true
    this.debugOverride = override
    try {
      AppManager.preference.preferences?.putSync(IAP_DEBUG_OVERRIDE_PREF_KEY, override)
      AppManager.preference.preferences?.flushSync()
    } catch (_) {
    }
    EventHelper.emitterPublish(REMOTE_CONTROL_ENTITLEMENT_CHANGED_EVENT)
  }

  /** 当前 Debug 测试状态对应的中文说明，仅供调试设置页展示。 */
  debugEntitlementOverrideText(): string {
    const override = this.loadDebugOverride()
    if (override === 'grant') {
      return '强制授予'
    }
    if (override === 'revoke') {
      return '强制收回'
    }
    return '跟随真实 IAP'
  }

  /** App 回到前台时使进程内缓存失效，下一次门禁必须等待 IAP 当前权益查询。 */
  invalidateEntitlement(): void {
    this.entitlementLoaded = false
  }

  /** 仅已保存过权益的用户在回到前台时联网复核，避免无购买用户产生无意义查询。 */
  async refreshEntitlementOnForeground(context: common.UIAbilityContext): Promise<void> {
    this.invalidateEntitlement()
    if (!this.remoteControlOwned && this.loadCachedReceipt().length === 0) {
      return
    }
    await this.refreshEntitlement(context)
  }

  private updateOwnedState(owned: boolean): void {
    const changed = this.remoteControlOwned !== owned
    this.remoteControlOwned = owned
    if (changed) {
      EventHelper.emitterPublish(REMOTE_CONTROL_ENTITLEMENT_CHANGED_EVENT)
    }
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

  private loadCachedPurchaseOrderId(): string {
    if (this.cachedPurchaseOrderIdLoaded) {
      return this.cachedPurchaseOrderId
    }
    this.cachedPurchaseOrderIdLoaded = true
    try {
      this.cachedPurchaseOrderId = AppManager.preference.preferences?.getSync(
        IAP_PURCHASE_ORDER_ID_PREF_KEY, '').toString() ?? ''
    } catch (_) {
      this.cachedPurchaseOrderId = ''
    }
    return this.cachedPurchaseOrderId
  }

  private loadDebugOverride(): IapDebugEntitlementOverride {
    if (!BuildProfile.DEBUG) {
      return 'real'
    }
    if (this.debugOverrideLoaded) {
      return this.debugOverride
    }
    this.debugOverrideLoaded = true
    try {
      const stored = AppManager.preference.preferences?.getSync(IAP_DEBUG_OVERRIDE_PREF_KEY, 'real').toString() ?? 'real'
      this.debugOverride = isIapDebugEntitlementOverride(stored) ? stored as IapDebugEntitlementOverride : 'real'
    } catch (_) {
      this.debugOverride = 'real'
    }
    return this.debugOverride
  }

  private loadValidatedAt(): number {
    if (this.validatedAtLoaded) {
      return this.validatedAt
    }
    this.validatedAtLoaded = true
    try {
      const stored = AppManager.preference.preferences?.getSync(IAP_ENTITLEMENT_VALIDATED_AT_PREF_KEY, '0')
        .toString() ?? '0'
      const parsed = Number.parseInt(stored)
      this.validatedAt = Number.isSafeInteger(parsed) && parsed > 0 ? parsed : 0
    } catch (_) {
      this.validatedAt = 0
    }
    return this.validatedAt
  }

  private persistVerifiedEntitlement(receipt: string, purchaseOrderId: string): void {
    this.cachedReceiptLoaded = true
    this.cachedReceipt = receipt
    this.cachedPurchaseOrderIdLoaded = true
    this.cachedPurchaseOrderId = purchaseOrderId
    this.validatedAtLoaded = true
    this.validatedAt = Date.now()
    this.updateOwnedState(true)
    try {
      AppManager.preference.preferences?.putSync(IAP_RECEIPT_PREF_KEY, receipt)
      AppManager.preference.preferences?.putSync(IAP_PURCHASE_ORDER_ID_PREF_KEY, this.cachedPurchaseOrderId)
      AppManager.preference.preferences?.putSync(IAP_ENTITLEMENT_VALIDATED_AT_PREF_KEY,
        this.validatedAt.toString())
      AppManager.preference.preferences?.deleteSync(LEGACY_IAP_OWNED_PREF_KEY)
      AppManager.preference.preferences?.flushSync()
    } catch (_) {
    }
  }

  private clearEntitlement(): void {
    this.cachedReceiptLoaded = true
    this.cachedReceipt = ''
    this.cachedPurchaseOrderIdLoaded = true
    this.cachedPurchaseOrderId = ''
    this.validatedAtLoaded = true
    this.validatedAt = 0
    this.updateOwnedState(false)
    try {
      AppManager.preference.preferences?.deleteSync(IAP_RECEIPT_PREF_KEY)
      AppManager.preference.preferences?.deleteSync(IAP_PURCHASE_ORDER_ID_PREF_KEY)
      AppManager.preference.preferences?.deleteSync(IAP_ENTITLEMENT_VALIDATED_AT_PREF_KEY)
      AppManager.preference.preferences?.deleteSync(LEGACY_IAP_OWNED_PREF_KEY)
      AppManager.preference.preferences?.flushSync()
    } catch (_) {
    }
  }

  private async restoreVerifiedCache(): Promise<boolean> {
    const receipt = this.loadCachedReceipt()
    if (receipt.length === 0) {
      this.updateOwnedState(false)
      return false
    }
    try {
      await verifyCachedPurchaseJws(receipt)
      let validatedAt = this.loadValidatedAt()
      if (validatedAt === 0) {
        // 升级前的合法收据获得一个宽限周期，等待下一次在线复核。
        validatedAt = Date.now()
        this.validatedAt = validatedAt
        try {
          AppManager.preference.preferences?.putSync(IAP_ENTITLEMENT_VALIDATED_AT_PREF_KEY,
            validatedAt.toString())
          AppManager.preference.preferences?.flushSync()
        } catch (_) {
        }
      }
      if (!isIapEntitlementValidationFresh(validatedAt)) {
        this.updateOwnedState(false)
        return false
      }
      this.updateOwnedState(true)
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
    this.persistVerifiedEntitlement(purchase.jwsPurchaseOrder, purchase.payload.purchaseOrderId ?? '')
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

  private async performEntitlementRefresh(context: common.UIAbilityContext): Promise<boolean> {
    this.loadCachedReceipt()
    this.checking = true
    this.refreshFailed = false
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
        this.persistVerifiedEntitlement(ownedPurchase.jwsPurchaseOrder, ownedPurchase.payload.purchaseOrderId ?? '')
      } else {
        this.clearEntitlement()
      }
      this.lastOnlineEntitlementCheckedAt = Date.now()
      this.lastOnlineEntitlementOwned = ownedPurchase !== undefined
      this.entitlementLoaded = true
      return ownedPurchase !== undefined
    } catch (error) {
      this.refreshFailed = true
      const err = error as BusinessError
      Logger.error(`refreshEntitlement failed: ${err.code} ${err.message}`, this)
      const restored = await this.restoreVerifiedCache()
      this.entitlementLoaded = restored
      return restored
    } finally {
      this.checking = false
    }
  }

  /** 联网刷新权益；并发调用复用同一次查询，失败时回退到本地已验签收据。 */
  async refreshEntitlement(context: common.UIAbilityContext, interactive: boolean = false): Promise<boolean> {
    let inFlight = this.refreshInFlight
    if (inFlight === undefined) {
      inFlight = this.performEntitlementRefresh(context)
      this.refreshInFlight = inFlight
    }
    try {
      const owned = await inFlight
      if (interactive && this.refreshFailed) {
        sendToast('无法连接应用市场，请确认已登录华为账号', $r('sys.symbol.exclamationmark_circle'), 1)
      }
      return owned
    } finally {
      if (this.refreshInFlight === inFlight) {
        this.refreshInFlight = undefined
      }
    }
  }

  /** 功能入口可复用 5 分钟内成功完成的在线权益查询；失败或离线回退不会写入该缓存。 */
  async refreshEntitlementForGate(context: common.UIAbilityContext): Promise<boolean> {
    const debugOverride = this.loadDebugOverride()
    if (BuildProfile.DEBUG && debugOverride !== 'real') {
      return debugOverride === 'grant'
    }
    if (isIapEntitlementGateCacheFresh(this.lastOnlineEntitlementCheckedAt)) {
      return applyIapDebugEntitlementOverride(this.lastOnlineEntitlementOwned, debugOverride, BuildProfile.DEBUG)
    }
    return this.refreshEntitlement(context)
  }

  /** 首次访问入口时的权益判定（带缓存） */
  async ensureEntitlementLoaded(context: common.UIAbilityContext): Promise<boolean> {
    if (this.entitlementLoaded) {
      return this.isRemoteControlUnlocked()
    }
    return this.refreshEntitlement(context)
  }

  private selectPromotionalOffer(product: iap.Product): iap.PromotionalOffer | undefined {
    const offers = product.promotionalOffers ?? []
    let selected: iap.PromotionalOffer | undefined = undefined
    for (let index = 0; index < offers.length; index += 1) {
      const candidate = offers[index]
      if (candidate.offerId.trim().length === 0 || !Number.isSafeInteger(candidate.microPrice)
        || candidate.microPrice < 0) {
        continue
      }
      if (selected === undefined || candidate.microPrice < selected.microPrice) {
        selected = candidate
      }
    }
    return selected
  }

  private async requestPromotionalJws(offerId: string): Promise<IapPromotionalJws> {
    const request: IapPromotionalJwsRequest = {
      purpose: 'remote_control_purchase',
      offerId: offerId
    }
    let result: cloudFunction.FunctionResult
    try {
      result = await this.callPromotionalJwsFunction(request)
    } catch (error) {
      const businessError = error as BusinessError
      if (!isIapPromotionalJwsInitialTransportError(businessError.code, businessError.message)) {
        throw new Error(businessError.message)
      }
      Logger.warn('cloud function HTTP task was not ready; retrying promotional JWS once', this)
      await delay(IAP_PROMOTIONAL_JWS_INITIAL_RETRY_DELAY_MS)
      result = await this.callPromotionalJwsFunction(request)
    }
    return parseIapPromotionalJwsResult(result.result, offerId)
  }

  private callPromotionalJwsFunction(request: IapPromotionalJwsRequest): Promise<cloudFunction.FunctionResult> {
    return cloudFunction.call({
      name: IAP_PROMOTIONAL_JWS_FUNCTION,
      version: '$latest',
      timeout: IAP_PROMOTIONAL_JWS_TIMEOUT_MS,
      data: request
    })
  }

  /** 查询商品展示价；自定义人群促销使用 promotionalOffers 中选定的单次优惠。 */
  async queryPrice(context: common.UIAbilityContext): Promise<IapPriceQuote> {
    this.price = ''
    this.originalPrice = ''
    this.promotionalPrice = false
    this.promotionalOfferId = ''
    try {
      const products = await iap.queryProducts(context, {
        productType: iap.ProductType.NONCONSUMABLE,
        productIds: [REMOTE_CONTROL_PRODUCT_ID]
      })
      if (BuildProfile.DEBUG) {
        hilog.info(IAP_DIAGNOSTIC_DOMAIN, IAP_DIAGNOSTIC_TAG, '%{public}s',
          `queryProducts returned count=${products.length}`)
        for (let index = 0; index < products.length; index += 1) {
          logIapProductDiagnostic(products[index], index)
        }
      }
      if (products.length > 0) {
        const product = products[0]
        const offer = this.selectPromotionalOffer(product)
        const productPrice = product.localPrice?.trim() ?? ''
        this.originalPrice = product.originalLocalPrice.trim()
        if (offer !== undefined) {
          this.price = offer.localPrice.trim()
          this.promotionalOfferId = offer.offerId.trim()
          this.promotionalPrice = this.price.length > 0 && this.originalPrice.length > 0 &&
            isIapPromotionalPrice(offer.microPrice, product.originalMicroPrice)
        } else {
          this.price = productPrice
          this.promotionalPrice = this.price.length > 0 && this.originalPrice.length > 0 &&
            isIapPromotionalPrice(product.microPrice, product.originalMicroPrice)
        }
        if (BuildProfile.DEBUG) {
          hilog.info(IAP_DIAGNOSTIC_DOMAIN, IAP_DIAGNOSTIC_TAG, '%{public}s',
            `selected price=${this.price} originalPrice=${this.originalPrice} ` +
              `promotional=${this.promotionalPrice} promotionalOfferId=${this.promotionalOfferId}`)
        }
      }
    } catch (error) {
      const err = error as BusinessError
      Logger.error(`queryProducts failed: ${err.code} ${err.message}`, this)
    }
    return new IapPriceQuote(this.price, this.originalPrice, this.promotionalPrice)
  }

  /** 发起购买，返回是否已获得权益 */
  async purchaseRemoteControl(context: common.UIAbilityContext): Promise<boolean> {
    this.loadCachedReceipt()
    try {
      await iap.queryEnvironmentStatus(context)
      const quotedOfferId = this.promotionalOfferId
      await this.queryPrice(context)
      if (quotedOfferId.length > 0 && this.promotionalOfferId !== quotedOfferId) {
        sendToast('当前优惠已变化，请刷新后重试', $r('sys.symbol.exclamationmark_circle'), 1)
        return false
      }
      let purchaseParameter: iap.PurchaseParameter
      if (this.promotionalOfferId.length > 0) {
        let promotionalJws: IapPromotionalJws
        try {
          promotionalJws = await this.requestPromotionalJws(this.promotionalOfferId)
        } catch (error) {
          Logger.error(`request promotional JWS failed: ${(error as Error).message}`, this)
          sendToast('暂时无法获取优惠，请稍后重试', $r('sys.symbol.exclamationmark_circle'), 1)
          return false
        }
        purchaseParameter = {
          productId: REMOTE_CONTROL_PRODUCT_ID,
          productType: iap.ProductType.NONCONSUMABLE,
          promotionalOfferId: promotionalJws.offerId,
          jwsRepresentation: promotionalJws.jwsRepresentation
        }
      } else {
        purchaseParameter = {
          productId: REMOTE_CONTROL_PRODUCT_ID,
          productType: iap.ProductType.NONCONSUMABLE
        }
      }
      if (BuildProfile.DEBUG) {
        hilog.info(IAP_DIAGNOSTIC_DOMAIN, IAP_DIAGNOSTIC_TAG, '%{public}s',
          `createPurchase promotionalOfferId=${this.promotionalOfferId} ` +
            `jwsRepresentation=${purchaseParameter.jwsRepresentation?.length ?? 0} bytes`)
      }
      const result = await iap.createPurchase(context, purchaseParameter)
      const purchase = await verifyPurchaseData(result.purchaseData)
      // 发放权益必须发生在 finishPurchase 之前，避免确认成功后本地发放失败。
      this.persistVerifiedEntitlement(purchase.jwsPurchaseOrder, purchase.payload.purchaseOrderId ?? '')
      // 购买前可能缓存了“未购买”；新订单必须使该入口缓存立即失效。
      this.lastOnlineEntitlementCheckedAt = 0
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

  /** 使用最近一次已验签订单号拉起华为官方退款申请页面。 */
  async requestRefund(context: common.UIAbilityContext): Promise<boolean> {
    await this.refreshEntitlement(context, true)
    if (!this.isRemoteControlUnlocked() && this.loadCachedPurchaseOrderId().length === 0) {
      sendToast('没有可申请退款的已购订单', $r('sys.symbol.exclamationmark_circle'), 1)
      return false
    }
    const purchaseOrderId = this.loadCachedPurchaseOrderId()
    if (purchaseOrderId.length === 0) {
      sendToast('当前测试权益没有真实订单，无法申请退款', $r('sys.symbol.exclamationmark_circle'), 1)
      return false
    }
    try {
      await iap.createRefundRequest(context, purchaseOrderId)
      sendToast('已提交退款申请，审核完成后权益将自动回收', $r('sys.symbol.checkmark_circle'), 0)
      return true
    } catch (error) {
      const err = error as BusinessError
      if (err.code === iap.IAPErrorCode.PURCHASE_ALREADY_REFUNDED) {
        sendToast('该订单已退款或正在退款', $r('sys.symbol.exclamationmark_circle'), 1)
      } else if (err.code === iap.IAPErrorCode.REFUND_NOT_ALLOWED) {
        sendToast('当前订单不允许申请退款', $r('sys.symbol.exclamationmark_circle'), 1)
      } else if (err.code === iap.IAPErrorCode.USER_CANCELED) {
        return false
      } else {
        Logger.error(`createRefundRequest failed: ${err.code} ${err.message}`, this)
        sendToast('无法打开退款申请，请稍后重试', $r('sys.symbol.exclamationmark_circle'), 1)
      }
      return false
    }
  }
}

export const IapService = new IapServiceClass()
