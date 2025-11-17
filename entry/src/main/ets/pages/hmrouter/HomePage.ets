import { HMRouter } from "@hadss/hmrouter"
import { AutoSortContainer } from "../nodes/AutoSortContainer";
import { deviceInfo } from "@kit.BasicServicesKit";
import { HdsNavigation, HdsNavigationTitleMode, HdsNavigationAttribute,
  IconStyleMode,
  ScrollEffectType} from "@hms.hds.hdsBaseComponent";
import { MenuButton } from "../Components";
import { requestDistributePerm } from "../../util/Permission";
import { LengthMetrics, SymbolGlyphModifier } from "@kit.ArkUI";

function symbolWithSize(symbol: Resource, size: number): SymbolGlyphModifier {
  let result = new SymbolGlyphModifier(symbol)
  result.fontSize(size)
  result.fontColor([$r("sys.color.font_primary")])
  return result
}

@HMRouter({ pageUrl: "HomePage" })
@ComponentV2
export struct HomePage {
  private myNodeController: AutoSortContainer = new AutoSortContainer();

  @Builder
  content() {
    Scroll() {
      NodeContainer(this.myNodeController)
        .width('100%')
        .layoutWeight(100)
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    }
    .width("100%")
    .height('100%')
    .backgroundColor($r("sys.color.background_secondary"))
    .align(Alignment.Top)
  }

  build() {
    if (deviceInfo.sdkApiVersion >= 20) {
      HdsNavigation() {
        this.content()
      }
      .mode(NavigationMode.Stack)
      .titleMode(HdsNavigationTitleMode.FREE)
      .titleBar({
        style: {
          scrollEffectOpts: {
            enableScrollEffect: true,
            scrollEffectType: ScrollEffectType.COMMON_BLUR,
            blurEffectiveStartOffset: LengthMetrics.vp(0),
            blurEffectiveEndOffset: LengthMetrics.vp(20)
          },
          originalStyle: {
            backgroundStyle: {
              backgroundColor: $r('sys.color.background_secondary'),
            },
            contentStyle: {
              titleStyle: {
                mainTitleColor: $r('sys.color.font_primary'),
                subTitleColor: $r('sys.color.font_secondary')
              },
              menuStyle: {
                backgroundColor: $r('sys.color.comp_background_tertiary'),
                iconColor: $r('sys.color.icon_primary')
              },
              backIconStyle: {
                backgroundColor: $r('sys.color.comp_background_tertiary'),
                iconColor: $r('sys.color.icon_primary')
              }
            }
          },
          scrollEffectStyle: {
            backgroundStyle: {
              backgroundColor: $r('sys.color.ohos_id_color_background_transparent'),
            },
            contentStyle: {
              titleStyle: {
                mainTitleColor: $r('sys.color.font_primary'),
                subTitleColor: $r('sys.color.font_secondary')
              },
              menuStyle: {
                backgroundColor: $r('sys.color.comp_background_tertiary'),
                iconColor: $r('sys.color.icon_primary')
              },
              backIconStyle: {
                backgroundColor: $r('sys.color.comp_background_tertiary'),
                iconColor: $r('sys.color.icon_primary')
              }
            }
          }
        },
        content: {
          title: {
            mainTitle: "EasyTier",
            subTitle: "v2.4.5"
          },
          menu: {
            value: [
              {
                content: {
                  icon: symbolWithSize($r("sys.symbol.plus"), 24),
                  label: "add",
                  action: ()=>{
                    requestDistributePerm(this.getUIContext().getHostContext()!, false).then(() => {

                    })
                  },
                  type: IconStyleMode.LARGE
                }
              },
              {
                content: {
                  icon: symbolWithSize($r("sys.symbol.gearshape"), 24),
                  label: "setting",
                  action: ()=>{

                  },
                  type: IconStyleMode.LARGE
                }
              }
            ]
          }
        },
        enableComponentSafeArea: true
      })
    }else {
      Navigation() {
        this.content()
      }
      .mode(NavigationMode.Stack)
      .titleMode(NavigationTitleMode.Free)
      .title({
        main: "EasyTier",
        sub: "v2.4.5"
      })
      .menus([
        MenuButton("add", $r("sys.symbol.plus"), () => {
          requestDistributePerm(this.getUIContext().getHostContext()!, false).then(() => {

          })
        }),
        MenuButton("setting", $r("sys.symbol.gearshape"), () => {

        }),
      ])
    }
  }
}