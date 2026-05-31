import { HMDefaultGlobalAnimator, HMNavigation, HMRouterMgr } from '@hadss/hmrouter';
import { AttributeUpdater, FrameCallback } from '@kit.ArkUI';
import { EventHelper } from '../util/EventHelper';
import { AppManager } from '../AppManager';
import { DialogHub, DialogMode } from '@hadss/dialoghub';
import { Logger } from '../shared/logging/Logger';
import { deferredLink } from '@kit.AppLinkingKit';
import { url } from '@kit.ArkTS';
import { unwrapUrl } from '../util/ShareUtil';

class MyNavModifier extends AttributeUpdater<NavigationAttribute> {
  initializeModifier(instance: NavigationAttribute): void {
    instance.hideNavBar(true);
  }
}

export class MyFrameCallback extends FrameCallback {
  callback: () => void

  constructor(callback: () => void) {
    super();
    this.callback = callback
  }

  onFrame() {
    this.callback()
  }
}

@Entry
@ComponentV2
export struct HMRouterIndex {
  modifier: MyNavModifier = new MyNavModifier();
  @Local dragOverlay: boolean = false
  compPos: Position | undefined
  dragType: string | undefined
  onlyDrag: boolean = false

  async aboutToAppear(): Promise<void> {
    DialogHub.init(this.getUIContext(), DialogMode.CUSTOM_DIALOG);
    try {
      await AppManager.init(this.getUIContext())
    } catch (error) {
      Logger.error(`AppManager init failed: ${JSON.stringify(error)}`, 'HMRouterIndex')
    }
    if (canIUse("SystemCapability.BundleManager.AppLinking.DeferredLink")) {
      EventHelper.commonListener("usual.event.PRIVACY_STATE_CHANGED", () => {
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
