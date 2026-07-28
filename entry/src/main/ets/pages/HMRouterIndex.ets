import { HMDefaultGlobalAnimator, HMNavigation, HMRouterMgr } from '@hadss/hmrouter';
import { AttributeUpdater } from '@kit.ArkUI';
import { EventHelper } from '../util/EventHelper';
import { AppManager } from '../AppManager';
import { Logger } from '../shared/logging/Logger';
import { deferredLink } from '@kit.AppLinkingKit';
import { url } from '@kit.ArkTS';
import { unwrapUrl } from '../util/ShareUtil';
import { warmEditRenderPlan } from '../config/render/EditRenderResolver';
import { startupMark } from '../services/runtime/StartupTrace';

class MyNavModifier extends AttributeUpdater<NavigationAttribute> {
  initializeModifier(instance: NavigationAttribute): void {
    instance.hideNavBar(true);
  }
}

@Entry
@ComponentV2
export struct HMRouterIndex {
  modifier: MyNavModifier = new MyNavModifier();
  private privacyStateUnsubscribe: (() => void) | undefined = undefined
  private active: boolean = false
  private appearGeneration: number = 0

  async aboutToAppear(): Promise<void> {
    startupMark('index.aboutToAppear.begin')
    this.active = true
    const generation = ++this.appearGeneration
    try {
      await AppManager.init(this.getUIContext())
    } catch (error) {
      Logger.error(`AppManager init failed: ${JSON.stringify(error)}`, 'HMRouterIndex')
    }
    startupMark('index.appManagerInit.done')
    if (!this.active || generation !== this.appearGeneration) {
      return
    }
    setTimeout(() => {
      warmEditRenderPlan()
    }, 0)
    if (canIUse("SystemCapability.BundleManager.AppLinking.DeferredLink") && !this.privacyStateUnsubscribe) {
      this.privacyStateUnsubscribe = EventHelper.commonListener("usual.event.PRIVACY_STATE_CHANGED", () => {
        deferredLink.popDeferredLink().then(async (link: string) => {
          if (link) {
            try {
              let urlObject = url.URL.parseURL(link);
              unwrapUrl(urlObject)
            } catch (_) {
            }
          }
        })
      })
    }
  }

  aboutToDisappear(): void {
    this.active = false
    this.appearGeneration += 1
    this.privacyStateUnsubscribe?.()
    this.privacyStateUnsubscribe = undefined
  }

  build() {
    Column() {
      HMNavigation({
        navigationId: 'MainNavigation', homePageUrl: 'HomePage',
        options: {
          dialogAnimator: HMDefaultGlobalAnimator.DIALOG_ANIMATOR,
          modifier: this.modifier
        }
      })
        .height('100%')
        .width('100%')
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    }
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .height('100%')
    .width('100%')
  }
}
