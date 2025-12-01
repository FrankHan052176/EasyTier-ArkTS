import { HMRouter, HMRouterMgr } from "@hadss/hmrouter"
import { deviceInfo } from "@kit.BasicServicesKit";
import { HdsNavigation, HdsNavigationTitleMode, IconStyleMode, HdsNavigationAttribute,
  ScrollEffectType} from "@hms.hds.hdsBaseComponent";
import { HdsMenuButton, MenuButton } from "../Components";
import { ColorMetrics, LengthMetrics, SymbolGlyphModifier } from "@kit.ArkUI";
import { AppManager } from "../../AppManager";
import { DesktopLayout } from "../nodes/DesktopLayout";
import { EventHelper } from "../../util/EventHelper";
import { SheetContent, SheetTitle } from "../../components/sheet/Basic";
import { HdsActionBar, ActionBarButton, ActionBarStyle } from "@kit.UIDesignKit";
import { sendToast } from "../../ToastUtil";
import { BottomAnimator } from "../../class/animator/BottomAnimator";

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
  @Local tips: string | undefined = ""
  @Local actionText: string | undefined = ""
  @Local actionBar: boolean = true

  aboutToAppear(): void {
    EventHelper.emitterListener("open_sheet", (data) => {
      let type = data.data!.type as string
      this.sheet_type = type
      this.sheet = true
    })
    EventHelper.emitterListener("close_sheet", () => {
      this.sheet = false
    })
  }

  @Builder
  actionBarAndError() {
    Column() {
      if (this.actionBar) {
        if (deviceInfo.sdkApiVersion >= 20) {
          HdsActionBar({
            startButtons: [new ActionBarButton({
              baseIcon: $r('sys.symbol.thumbnails'),
              onClick: () => {
                HMRouterMgr.to('StatusPage')
                  .withParam(AppManager.easytier.selected)
                  .withAnimator(new BottomAnimator())
                  .pushAsync()
              }
            })],
            endButtons: [new ActionBarButton({
              baseIcon: $r('sys.symbol.arrow_clockwise'),
              onClick: () => {
                if (AppManager.easytier.runningNetworks.size > 0) {
                  let uuid = ""
                  for (const key of AppManager.easytier.runningNetworks.keys()) {
                    uuid = key
                    break;
                  }
                  AppManager.easytier.stop()
                  if (!AppManager.easytier.start(uuid)) {
                    sendToast("非法实例, 很可能是序列化错误, 请上报日志.", $r("sys.symbol.exclamationmark_circle"), 1)
                  }
                }else {
                  sendToast("Amazing!找不到启动的实例", $r("sys.symbol.exclamationmark_circle"), 1)
                }
              }
            })],
            primaryButton: new ActionBarButton({
              baseIcon: $r('sys.symbol.play_fill'),
              altIcon: $r('sys.symbol.pause_fill'),
              onClick: () => {
                if (AppManager.easytier.runningNetworks.size > 0) {
                  AppManager.easytier.stop()
                }else {
                  AppManager.easytier.start()
                }
              },
              hoverTips: '启停'
            }),
            actionBarStyle: new ActionBarStyle({
              backgroundBlurStyle: BlurStyle.COMPONENT_ULTRA_THIN,
              isPrimaryIconChanged: AppManager.easytier.runningNetworks.size > 0,
              backgroundColor: ColorMetrics.resourceColor($r("sys.color.interactive_select"))
            }),
            isExpand: AppManager.easytier.runningNetworks.size > 0
          })
        }else {
          // TODO 20- actionbar
        }
      }
    }
    .alignItems(HorizontalAlign.Center)
    .justifyContent(FlexAlign.End)
    .height('100%')
    .width('100%')
    .hitTestBehavior(HitTestMode.Transparent)
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
    .overlay(this.actionBarAndError, {
      align: Alignment.Center
    })
  }

  build() {
    Column() {
      if (deviceInfo.sdkApiVersion >= 20) {
        HdsNavigation() {
          this.content()
        }
        .height('100%')
        .width('100%')
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
                HdsMenuButton("new", $r("sys.symbol.plus"), () => {
                  AppManager.permission.requestDistributePerm(false).then(() => {
                    EventHelper.emitterPublish("open_sheet",{
                      data: {
                        type: "new"
                      }
                    })
                  })
                }),
                HdsMenuButton("setting", $r("sys.symbol.gearshape"), () => {
                  EventHelper.emitterPublish("open_sheet",{
                    data: {
                      type: "setting"
                    }
                  })
                })
              ]
            }
          }
        })
        .mode(NavigationMode.Stack)
        .titleMode(HdsNavigationTitleMode.FREE)
        .hideBackButton(true)
        .hideTitleBar(false)
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      }else {
        Navigation() {
          this.content()
        }
        .height('100%')
        .width('100%')
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
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      }
    }
    .height('100%')
    .width('100%')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .bindSheet(this.sheet, SheetContent(this.sheet_type), {
      height: this.sheet_type === "setting"?SheetSize.LARGE:SheetSize.FIT_CONTENT,
      preferType: SheetType.CENTER,
      showClose: false,
      dragBar: false,
      blurStyle: BlurStyle.Thin,
      title: SheetTitle(this.sheet_type),
      onWillDismiss: () => {
        this.sheet = false
      }
    })
  }
}