import { ConfigField, ContentUtil } from '../../ContentUtil'
import { NetworkConfig } from '../../protobuf/api_manage'
import { FieldEdit } from '../../components/edit/FieldEdit'
import { HMRouter, HMRouterMgr } from '@hadss/hmrouter'
import { deviceInfo } from '@kit.BasicServicesKit'
import { HdsNavigation, HdsNavigationTitleMode, IconStyleMode, ScrollEffectType, HdsNavigationAttribute } from '@kit.UIDesignKit'
import { LengthMetrics } from '@kit.ArkUI'
import { symbolWithSize } from './HomePage'
import { AppManager } from '../../AppManager'
import { MenuButton } from '../Components'

@HMRouter({ pageUrl: "EditPage" })
@ComponentV2
export struct EditPage {
  @Local uuid: string | null = null;
  @Local name: string | null = null;
  @Local config: NetworkConfig | null = null;
  scroller: Scroller = new Scroller();

  aboutToAppear(): void {
    this.name = HMRouterMgr.getCurrentParam() as string;
    this.uuid = AppManager.data.configNameUUIDMap.get(this.name)!
    this.config = AppManager.data.configUUIDMap.get(this.uuid)!
  }

  @Builder
  content() {
    List({space: 10, scroller: this.scroller}) {
      ListItem()
        .width('100%')
        .height(138)
      ForEach(ContentUtil.fieldList, (field: ConfigField) => {
        ListItem(){
          FieldEdit({config: this.config!, field: field})
            .width('100%')
        }
      })
    }
    .scrollBar(BarState.Off)
    .chainAnimation(true)
    .edgeEffect(EdgeEffect.None)
    .padding({left: 10, right: 10})
    .width('100%')
    .height('100%')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  build() {
    Column() {
      if (deviceInfo.sdkApiVersion >= 20) {
        HdsNavigation() {
          this.content()
        }
        .bindToScrollable([this.scroller])
        .titleBar({
          style: {
            scrollEffectOpts: {
              enableScrollEffect: true,
              scrollEffectType: ScrollEffectType.GRADUAL_BLUR,
              blurEffectiveStartOffset: LengthMetrics.vp(0),
              blurEffectiveEndOffset: LengthMetrics.vp(20),
            },
            originalStyle: {
              contentStyle: {
                titleStyle: {
                  mainTitleColor: $r("sys.color.font_primary"),
                  subTitleColor: $r("sys.color.font_secondary")
                },
                menuStyle: {
                  backgroundColor: $r("sys.color.interactive_hover")
                }
              }
            }
          },
          content: {
            title: {
              mainTitle: this.name!,
              subTitle: this.uuid!
            },
            menu: {
              value: [
                {
                  content: {
                    icon: symbolWithSize(AppManager.data.isFavorite(this.uuid!)?$r("sys.symbol.star_fill"):$r("sys.symbol.star"), 24),
                    label: "favorite",
                    isEnabled: true,
                    action: ()=>{
                      AppManager.data.changeFavorite(this.uuid!)
                    },
                    type: IconStyleMode.LARGE
                  }
                },
                {
                  content: {
                    icon: symbolWithSize($r("sys.symbol.rectangle_and_arrowshape_turn_up_right_fill"), 24),
                    label: "share",
                    isEnabled: true,
                    action: ()=>{

                    },
                    type: IconStyleMode.LARGE
                  }
                },
                {
                  content: {
                    icon: symbolWithSize($r("sys.symbol.trash"), 24),
                    label: "delete",
                    isEnabled: true,
                    action: ()=>{

                    },
                    type: IconStyleMode.LARGE
                  }
                }
              ]
            }
          }
        })
        .systemBarStyle({statusBarContentColor: AppManager.preference.color_mode > 0?"#000000":"#FFFFFF"},{statusBarContentColor: AppManager.preference.color_mode > 0?"#000000":"#FFFFFF"})
        .mode(NavigationMode.Stack)
        .titleMode(HdsNavigationTitleMode.FREE)
        .hideBackButton(true)
        .hideTitleBar(false)
      }else {
        Navigation() {
          this.content()
        }
        .mode(NavigationMode.Stack)
        .titleMode(NavigationTitleMode.Free)
        .title({
          main: this.name!,
          sub: this.uuid!
        }, {
          backgroundColor: $r('sys.color.background_secondary')
        })
        .menus([
          MenuButton("favorite", AppManager.data.isFavorite(this.uuid!)?$r("sys.symbol.star_fill"):$r("sys.symbol.star"), () => {
            AppManager.data.changeFavorite(this.uuid!)
          }),
          MenuButton("share", $r("sys.symbol.rectangle_and_arrowshape_turn_up_right_fill"), () => {
            AppManager.data.isFavorite(this.uuid!)?$r("sys.symbol.star_fill"):$r("sys.symbol.star")
          }),
          MenuButton("delete", $r("sys.symbol.trash"), () => {

          }),
        ])
      }
    }
    .backgroundColor($r('sys.color.background_secondary'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}