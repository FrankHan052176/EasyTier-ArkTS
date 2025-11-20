import { HMDefaultGlobalAnimator, HMNavigation } from "@hadss/hmrouter";
import { AttributeUpdater } from "@kit.ArkUI";
import { EventHelper } from "../util/EventHelper";

class MyNavModifier extends AttributeUpdater<NavigationAttribute> {
  initializeModifier(instance: NavigationAttribute): void {
    instance.hideNavBar(true);
  }
}

@Entry
@ComponentV2
export struct HMRouterIndex {
  modifier: MyNavModifier = new MyNavModifier();

  build() {
    Column(){
      HMNavigation({
        navigationId: 'MainNavigation', homePageUrl: 'HomePage',
        options: {
          standardAnimator: HMDefaultGlobalAnimator.STANDARD_ANIMATOR,
          dialogAnimator: HMDefaultGlobalAnimator.DIALOG_ANIMATOR,
          modifier: this.modifier
        }
      })
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    }
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .height('100%')
    .width('100%')
    .onTouch((event) => {
      if (event.type == TouchType.Down) {
        EventHelper.emitterPublish("resize_off")
        EventHelper.emitterPublish("click_edit")
      }
    })
  }
}