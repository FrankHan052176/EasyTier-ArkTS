import { HMRouter } from "@hadss/hmrouter"
import { deviceInfo } from "@kit.BasicServicesKit";
import { HdsNavigation, HdsNavigationTitleMode, IconStyleMode, HdsNavigationAttribute,
  ScrollEffectType} from "@hms.hds.hdsBaseComponent";
import { MenuButton } from "../Components";
import { LengthMetrics, SymbolGlyphModifier } from "@kit.ArkUI";
import { AppManager } from "../../AppManager";
import { DesktopLayout } from "../nodes/DesktopLayout";
import { EventHelper } from "../../util/EventHelper";
import { SheetContent, SheetTitle } from "../../components/sheet/Basic";

export function symbolWithSize(symbol: Resource, size: number): SymbolGlyphModifier {
  let result = new SymbolGlyphModifier(symbol)
  result.fontSize(size)
  result.fontColor([$r("sys.color.font_primary")])
  return result
}

@HMRouter({ pageUrl: "HomePage" })
@ComponentV2
export struct HomePage {
  scroller: Scroller = new Scroller();
  @Local sheet: boolean = false
  @Local sheet_type: string = ""

  aboutToAppear(): void {
    EventHelper.emitterListener("open_sheet", (data) => {
      let type = data.data!.type as string
      if (!this.sheet) {
        this.sheet_type = type
        this.sheet = true
      }
    })
    EventHelper.emitterListener("close_sheet", () => {
      this.sheet = false
    })
  }

  @Builder
  content() {
    Scroll(this.scroller) {
      Column() {
        if (deviceInfo.sdkApiVersion >= 20) {
          Column()
            .width('100%')
            .height(138)
        }
        DesktopLayout()
      }
    }
    .width("100%")
    .height('100%')
    .backgroundColor($r("sys.color.background_secondary"))
    .align(Alignment.Top)
    .scrollBar(BarState.Off)
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
              mainTitle: "EasyTier",
              subTitle: "v2.4.5"
            },
            menu: {
              value: [
                {
                  content: {
                    icon: symbolWithSize($r("sys.symbol.plus"), 24),
                    label: "new",
                    isEnabled: true,
                    action: ()=>{
                      AppManager.permission.requestDistributePerm(false).then(() => {
                        EventHelper.emitterPublish("open_sheet",{
                          data: {
                            type: "new"
                          }
                        })
                      })
                    },
                    type: IconStyleMode.LARGE
                  }
                },
                {
                  content: {
                    icon: symbolWithSize($r("sys.symbol.gearshape"), 24),
                    label: "setting",
                    isEnabled: true,
                    action: ()=>{
                      EventHelper.emitterPublish("open_sheet",{
                        data: {
                          type: "setting"
                        }
                      })
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
          main: "EasyTier",
          sub: "v2.4.5"
        }, {
          backgroundColor: $r('sys.color.background_secondary')
        })
        .menus([
          MenuButton("new", $r("sys.symbol.plus"), () => {
            AppManager.permission.requestDistributePerm(false).then(() => {
              EventHelper.emitterPublish("open_sheet",{
                data: {
                  type: "new"
                }
              })
            })
          }),
          MenuButton("setting", $r("sys.symbol.gearshape"), () => {
            EventHelper.emitterPublish("open_sheet",{
              data: {
                type: "setting"
              }
            })
          }),
        ])
      }
    }
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .bindSheet($$this.sheet, SheetContent(this.sheet_type), {
      height: SheetSize.FIT_CONTENT,
      preferType: SheetType.CENTER,
      showClose: false,
      dragBar: false,
      blurStyle: BlurStyle.Thin,
      title: SheetTitle(this.sheet_type)
    })
  }
}