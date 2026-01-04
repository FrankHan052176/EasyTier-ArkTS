import { HMRouter, HMRouterMgr } from '@hadss/hmrouter';
import { deviceInfo } from '@kit.BasicServicesKit';
import {
  HdsNavigation,
  HdsNavigationTitleMode,
  ScrollEffectType,
  HdsNavigationAttribute
} from '@hms.hds.hdsBaseComponent';
import { HdsMenuButton, MenuButton } from '../Components';
import { ColorMetrics, curves, LengthMetrics, SymbolGlyphModifier } from '@kit.ArkUI';
import { AppManager } from '../../AppManager';
import { DesktopLayout } from '../nodes/DesktopLayout';
import { EventHelper } from '../../util/EventHelper';
import { SheetContentBuilder, SheetTitleBuilder } from '../../components/sheet/Basic';
import { ActionBarButton, ActionBarStyle, HdsActionBar } from '@kit.UIDesignKit';
import { sendToast } from '../../ToastUtil';
import { BottomAnimator } from '../../class/animator/BottomAnimator';
import { motion } from '@kit.MultimodalAwarenessKit';
import { harmonyShare, systemShare } from '@kit.ShareKit';
import { compressStr } from '../../CompressUtil';
import { uniformTypeDescriptor } from '@kit.ArkData';
import { Logger } from '../../util/Logger';
import { mappedJson } from '../../MappedUtil';
import { WindowUtil } from '../../WindowUtil';

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
  @Local hand: number = 0

  aboutToAppear(): void {
    EventHelper.emitterListener("home_open_sheet", (data) => {
      this.sheet_type = data.data!.type as string
      this.sheet = true
    })
    EventHelper.emitterListener("home_close_sheet", () => {
      this.sheet = false
    })
    EventHelper.emitterListener("reset_holding_detector", () => {
      this.hand = 0
    })
    if (canIUse("SystemCapability.MultimodalAwareness.Motion")) {
      if (deviceInfo.sdkApiVersion >= 20) {
        try {
          motion.on('holdingHandChanged', (data: motion.HoldingHandStatus) => {
            switch (data) {
              case motion.HoldingHandStatus.LEFT_HAND_HELD:
              case motion.HoldingHandStatus.RIGHT_HAND_HELD: {
                if (AppManager.preference.holding_detector) {
                  animateToImmediately({
                    duration: 300,
                    curve: curves.springMotion(0.5, 0.6, 0)
                  }, () => {
                    this.hand = data
                  })
                }
                break;
              }
              default: {
                animateToImmediately({
                  duration: 300,
                  curve: curves.springMotion(0.5, 0.6, 0)
                }, () => {
                  this.hand = 0
                })
              }
            }
          })
        } catch (_) {
        }
      }
    }
    harmonyShare.on('knockShare', (target) => {
      this.immersiveCallback(target)
    });
  }

  aboutToDisappear(): void {
    harmonyShare.off('knockShare', (target) => {
      this.immersiveCallback(target)
    });
  }

  restart() {
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
    } else {
      sendToast("Amazing!找不到启动的实例", $r("sys.symbol.exclamationmark_circle"), 1)
    }
  }

  startAndStop() {
    if (AppManager.easytier.runningNetworks.size > 0) {
      AppManager.easytier.stop()
    } else {
      AppManager.easytier.start()
    }
  }

  status() {
    let uuid = AppManager.easytier.selected
    if (!uuid || !AppManager.easytier.runningNetworks.has(uuid)) {
      if (AppManager.easytier.runningNetworks.size > 0) {
        uuid = AppManager.easytier.runningNetworks.keys()
          .next()
          .value
      }
    }
    if (uuid) {
      HMRouterMgr.to('StatusPage')
        .withParam(uuid)
        .withAnimator(new BottomAnimator())
        .pushAsync()
    }
  }

  @Builder
  actionBar() {
    Column() {
      if (deviceInfo.sdkApiVersion >= 20) {
        HdsActionBar({
          startButtons: [new ActionBarButton({
            baseIcon: $r('sys.symbol.thumbnails'),
            onClick: () => {
              this.status()
            }
          })],
          endButtons: [new ActionBarButton({
            baseIcon: $r('sys.symbol.arrow_clockwise'),
            onClick: () => {
              this.restart()
            }
          })],
          primaryButton: new ActionBarButton({
            baseIcon: $r('sys.symbol.play_fill'),
            altIcon: $r('sys.symbol.pause_fill'),
            onClick: () => {
              this.startAndStop()
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
      } else {
        Row() {
          if (AppManager.easytier.runningNetworks.size > 0) {
            Button({ type: ButtonType.Circle }) {
              SymbolGlyph($r('sys.symbol.thumbnails'))
                .fontSize(24)
                .fontColor([$r("sys.color.font_primary")])
            }
            .width(48)
            .height(48)
            .backgroundColor(Color.Transparent)
            .onClick(() => {
              this.status()
            })
          }

          Button({ type: ButtonType.Circle }) {
            SymbolGlyph(AppManager.easytier.runningNetworks.size > 0 ? $r('sys.symbol.pause_fill') :
              $r('sys.symbol.play_fill'))
              .fontSize(28)
              .fontColor([$r("sys.color.font_primary")])
          }
          .width(56)
          .height(56)
          .backgroundColor(Color.Transparent)
          .onClick(() => {
            this.startAndStop()
          })

          if (AppManager.easytier.runningNetworks.size > 0) {
            Button({ type: ButtonType.Circle }) {
              SymbolGlyph($r('sys.symbol.arrow_clockwise'))
                .fontSize(24)
                .fontColor([$r("sys.color.font_primary")])
            }
            .width(48)
            .height(48)
            .backgroundColor(Color.Transparent)
            .onClick(() => {
              this.restart()
            })
          }
        }
        .padding(8)
        .backgroundColor($r("sys.color.interactive_select"))
        .backgroundBlurStyle(BlurStyle.COMPONENT_ULTRA_THIN)
        .borderRadius(36)
        .margin({ bottom: 12 })
        .shadow(ShadowStyle.OUTER_DEFAULT_SM)
        .animation({ duration: 300, curve: Curve.Friction })
      }
    }
    .alignItems(this.hand === 1 ? HorizontalAlign.Start :
      (this.hand === 2 ? HorizontalAlign.End : HorizontalAlign.Center))
    .justifyContent(FlexAlign.End)
    .height('100%')
    .width('100%')
    .hitTestBehavior(HitTestMode.Transparent)
    .padding({ left: 20, right: 20 })
  }

  @Builder
  content() {
    Scroll() {
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
    .edgeEffect(EdgeEffect.Spring)
  }

  build() {
    Column() {
      if (deviceInfo.sdkApiVersion >= 20) {
        HdsNavigation() {
          this.content()
        }
        .height('100%')
        .width('100%')
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
                    this.sheet_type = "new"
                    this.sheet = true
                  })
                }),
                HdsMenuButton("setting", $r("sys.symbol.gearshape"), () => {
                  this.sheet_type = "setting"
                  this.sheet = true
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
      } else {
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
              this.sheet_type = "new"
              this.sheet = true
            })
          }),
          MenuButton("setting", $r("sys.symbol.gearshape"), () => {
            this.sheet_type = "setting"
            this.sheet = true
          }),
        ])
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      }
    }
    .height('100%')
    .width('100%')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .bindSheet(this.sheet, SheetContentBuilder(this.sheet_type), {
      height: this.sheet_type === "setting" ? SheetSize.LARGE : SheetSize.FIT_CONTENT,
      preferType: SheetType.CENTER,
      showClose: false,
      dragBar: false,
      blurStyle: BlurStyle.Thin,
      title: SheetTitleBuilder(this.sheet_type),
      onWillDismiss: (action) => {
        if (action.reason != DismissReason.SLIDE_DOWN) {
          action.dismiss()
          this.sheet = false
        }
      }
    })
    .overlay(this.actionBar, {
      align: Alignment.Bottom,
      offset: {
        x: 0,
        y: WindowUtil.statusBarHeight
      }
    })
  }

  private immersiveCallback(sharableTarget: harmonyShare.SharableTarget) {
    if (AppManager.easytier.selected) {
      let config = AppManager.data.configUUIDMap.get(AppManager.easytier.selected)
      if (config) {
        compressStr(mappedJson(config)).then((data) => {
          try {
            let shareData: systemShare.SharedData = new systemShare.SharedData({
              utd: uniformTypeDescriptor.UniformDataType.HYPERLINK,
              content: 'https://easytier.cn/comp_cfg?cfg=' + data,
              title: '分享配置 ' + AppManager.data.configUUIDNameMap.get(AppManager.easytier.selected!),
              description: AppManager.easytier.selected ?? ""
            });
            sharableTarget.share(shareData);
          } catch (e) {
            Logger.error("systemShare" + JSON.stringify(e), "HomePage")
          }
        }).catch((e: Error) => {
          Logger.error("compressedConfig" + JSON.stringify(e), "HomePage")
        })
      }
    } else {
      sendToast("先选择一个实例，再分享吧")
    }
  }
}