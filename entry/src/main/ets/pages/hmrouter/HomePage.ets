import { HMRouter, HMRouterMgr } from '@hadss/hmrouter';
import { deviceInfo, emitter } from '@kit.BasicServicesKit';
import {
  HdsNavigation,
  HdsNavigationTitleMode,
  HdsNavigationAttribute,
  TitleBarStyleOptions
} from '@hms.hds.hdsBaseComponent';
import { HdsMenuButton } from '../Components';
import { ColorMetrics, curves, LengthMetrics } from '@kit.ArkUI';
import { AppManager } from '../../AppManager';
import { EventHelper } from '../../util/EventHelper';
import { HomeSheetContentBuilder } from '../../components/sheet/HomeSheet';
import { setConfigName } from '../../components/sheet/NewConfig';
import { ActionBarButton, ActionBarStyle, HdsActionBar, hdsMaterial } from '@kit.UIDesignKit';
import { sendToast } from '../../ToastUtil';
import { BottomAnimator } from '../../class/animator/BottomAnimator';
import { motion } from '@kit.MultimodalAwarenessKit';
import { harmonyShare } from '@kit.ShareKit';
import { WindowUtil } from '../../WindowUtil';
import { buildShareData, buildShareUrlSync } from '../../util/ShareUtil';
import { ConfigJson } from '../../config/schema/SchemaConfig';
import { Instances } from '../../components/index/Instances';
import { Favorite } from '../../components/index/Favorite';
import { Logs as Logs } from '../../components/index/Logs';
import { QQGroups } from '../../components/index/QQGroups';
import { SharedPeers } from '../../components/index/SharedPeers'
import { CompSizeWithPos, DesktopLayout } from 'desktop_layout';
import { generateBarcode, scanCore } from '@kit.ScanKit';
import { image } from '@kit.ImageKit';
import { QRDialog } from '../../components/util/QRImage';

@Builder
function buildComp(type: string) {
  if (type == "Instances") {
    Instances()
  } else if (type === "Favorite") {
    Favorite()
  } else if (type === "Logs") {
    Logs()
  } else if (type === "SharedPeers") {
    SharedPeers()
  } else if (type === "QQ") {
    QQGroups()
  } else {
    Text(type)
      .fontSize(50)
      .fontWeight(FontWeight.Bold)
      .margin({ bottom: 36 })
  }
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
  private qrPixelMap: image.PixelMap | undefined = undefined
  private qrDialogController: CustomDialogController | null = null
  private active: boolean = false
  private qrRequestId: number = 0
  private homeOpenSheetCallback = (data: emitter.EventData) => {
    this.sheet_type = data.data!.type as string
    this.sheet = true
  }
  private homeCloseSheetCallback = () => {
    this.closeHomeSheet()
  }
  private resetHoldingDetectorCallback = () => {
    this.hand = 0
  }
  private holdingHandChangedCallback = (data: motion.HoldingHandStatus) => {
    switch (data) {
      case motion.HoldingHandStatus.LEFT_HAND_HELD:
      case motion.HoldingHandStatus.RIGHT_HAND_HELD: {
        if (AppManager.uiState.holding_detector) {
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
  }
  private holdingHandRegistered: boolean = false

  private closeHomeSheet(): void {
    if (this.sheet_type === 'new') {
      setConfigName(undefined)
    }
    this.sheet = false
    this.sheet_type = ''
  }

  aboutToAppear(): void {
    this.active = true
    EventHelper.emitterListener("home_open_sheet", this.homeOpenSheetCallback)
    EventHelper.emitterListener("home_close_sheet", this.homeCloseSheetCallback)
    EventHelper.emitterListener("reset_holding_detector", this.resetHoldingDetectorCallback)
    if (canIUse("SystemCapability.MultimodalAwareness.Motion")) {
      if (deviceInfo.sdkApiVersion >= 20) {
        try {
          motion.on('holdingHandChanged', this.holdingHandChangedCallback)
          this.holdingHandRegistered = true
        } catch (_) {
        }
      }
    }
    harmonyShare.on('knockShare', this.immersiveCallback);
    if (AppManager.uiState.help2) {
      setTimeout(() => {
        AppManager.uiState.help2 = false
      }, 100)
      HMRouterMgr.to("HelpPage").push()
    }
  }

  aboutToDisappear(): void {
    this.active = false
    this.closeQrDialog()
    EventHelper.emitterOff("home_open_sheet", this.homeOpenSheetCallback)
    EventHelper.emitterOff("home_close_sheet", this.homeCloseSheetCallback)
    EventHelper.emitterOff("reset_holding_detector", this.resetHoldingDetectorCallback)
    harmonyShare.off('knockShare', this.immersiveCallback);
    if (this.holdingHandRegistered) {
      try {
        motion.off('holdingHandChanged', this.holdingHandChangedCallback)
      } catch (_) {
      }
      this.holdingHandRegistered = false
    }
  }

  private releaseQrPixelMap(): void {
    const pixelMap = this.qrPixelMap
    this.qrPixelMap = undefined
    if (pixelMap) {
      pixelMap.release().catch(() => {
      })
    }
  }

  private resetQrDialog(): void {
    const controller = this.qrDialogController
    this.qrDialogController = null
    if (controller) {
      try {
        controller.close()
      } catch (_) {
      }
    }
    this.releaseQrPixelMap()
  }

  private closeQrDialog(): void {
    this.qrRequestId++
    this.resetQrDialog()
  }

  private openQrDialog(pixelMap: image.PixelMap): void {
    const controller: CustomDialogController = new CustomDialogController({
      builder: QRDialog({ pixelMap }),
      autoCancel: true,
      alignment: DialogAlignment.Center,
      customStyle: true,
      isModal: true,
      maskColor: 'rgba(0,0,0,0.35)',
      cancel: () => {
        if (this.qrDialogController === controller) {
          this.qrDialogController = null
        }
        this.releaseQrPixelMap()
      }
    })
    this.qrPixelMap = pixelMap
    this.qrDialogController = controller
    controller.open()
  }

  startAndStop() {
    if (AppManager.easytier.runningNetworks.size > 0) {
      AppManager.easytier.stop()
    } else {
      AppManager.easytier.start()
    }
  }

  status() {
    let uuid = AppManager.uiState.selected
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

  async qr(): Promise<void> {
    if (!AppManager.uiState.selected) {
      return
    }
    let config: ConfigJson | undefined = AppManager.easytier.getConfig(AppManager.uiState.selected)
    if (!config) {
      return
    }
    const requestId = ++this.qrRequestId
    this.resetQrDialog()
    try {
      const content = await buildShareUrlSync(config, true)
      if (!this.active || requestId !== this.qrRequestId) {
        return
      }
      if (content.length === 0) {
        sendToast('二维码生成失败', $r('sys.symbol.exclamationmark_circle'), 1)
        return
      }
      let options: generateBarcode.CreateOptions = {
        scanType: scanCore.ScanType.QR_CODE,
        height: 400,
        width: 400
      }
      const pixelMap = await generateBarcode.createBarcode(content, options)
      if (!this.active || requestId !== this.qrRequestId) {
        pixelMap.release().catch(() => {
        })
        return
      }
      this.openQrDialog(pixelMap)
    } catch (_) {
      if (!this.active || requestId !== this.qrRequestId) {
        return
      }
      sendToast('二维码生成失败', $r('sys.symbol.exclamationmark_circle'), 1)
    }
  }

  @Builder
  actionBar() {
    Column() {
      HdsActionBar({
        startButtons: [new ActionBarButton({
          baseIcon: $r('sys.symbol.thumbnails'),
          onClick: () => {
            this.status()
          }
        })],
        endButtons: [new ActionBarButton({
          baseIcon: $r('sys.symbol.qrcode'),
          onClick: () => {
            this.qr()
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
        Column()
          .width('100%')
          .height(138)

        DesktopLayout({
          comp_sequence: AppManager.uiState.raw_comp_sequence.split("|").map((value) => {
            let raw = value.split("_")
            return {
              type: raw[0],
              x: Number.parseInt(raw[1]),
              y: Number.parseInt(raw[2]),
              width: Number.parseInt(raw[3]),
              height: Number.parseInt(raw[4])
            } as CompSizeWithPos
          }),
          types: ["Instances", "Logs", "Favorite", "SharedPeers", "QQ"],
          saveSequence: (layout) => {
            let sequenceData = ""
            layout.comp_sequence.forEach((type) => {
              let size = layout.getCompSize(type)
              sequenceData += `${type}_${size.grid_x}_${size.grid_y}_${size.lane_w}_${size.lane_h}|`
            })
            AppManager.preference.updateSequence(sequenceData.length > 0 ?
              sequenceData.substring(0, sequenceData.length - 1) :
              sequenceData)
          },
          contentBuilder: wrapBuilder(buildComp),
          name: "home",
          hasWidgetList: ["Favorite"],
          formWantFunc: (comp_type) => {
            return {
              bundleName: "top.frankhan.easytier",
              abilityName: 'EntryFormAbility',
              parameters: {
                'ohos.extra.param.key.form_dimension': 1,
                'ohos.extra.param.key.form_name': comp_type.toLowerCase() + "_widget",
                'ohos.extra.param.key.module_name': 'entry'
              }
            }
          },
          breakpoints: [
            { breakpoint: 0, columns: 2 },
            { breakpoint: 720, columns: 4 },
            { breakpoint: 960, columns: 6 }
          ],
          maxCompW: 2,
          maxCompH: 2
        })
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

  navTitleStyle(): TitleBarStyleOptions {
    if (deviceInfo.distributionOSApiVersion >= 60100 && hdsMaterial.getSystemMaterialTypes().length > 0) {
      return {
        scrollEffectOpts: {
          enableScrollEffect: true,
          scrollEffectType: deviceInfo.sdkApiVersion >= 23 ? 3 : 2,
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
              iconColor: $r("sys.color.font_primary")
            },
            backIconStyle: {
              iconColor: $r("sys.color.font_primary")
            }
          }
        },
        systemMaterialEffect: {
          materialType: hdsMaterial.MaterialType.ADAPTIVE,
          materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
        }
      }
    }else {
      return {
        scrollEffectOpts: {
          enableScrollEffect: true,
          scrollEffectType: deviceInfo.sdkApiVersion >= 23 ? 3 : 2,
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
              iconColor: $r("sys.color.font_primary"),
              backgroundColor: $r("sys.color.background_primary")
            },
            backIconStyle: {
              iconColor: $r("sys.color.font_primary"),
              backgroundColor: $r("sys.color.background_primary")
            }
          }
        }
      }
    }
  }

  build() {
    HdsNavigation() {
      this.content()
    }
    .height('100%')
    .width('100%')
    .titleBar({
      style: this.navTitleStyle(),
      content: {
        title: {
          mainTitle: "EasyTier",
          subTitle: "v" + AppManager.easytier.version().split("-")[0]
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
    .height('100%')
    .width('100%')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .bindSheet(this.sheet, HomeSheetContentBuilder(this.sheet_type), {
      height: this.sheet_type === "new" ? SheetSize.MEDIUM : SheetSize.LARGE,
      preferType: SheetType.CENTER,
      showClose: false,
      enableFloatingDragBar: true,
      onWillDismiss: (action) => {
        if (action.reason != DismissReason.SLIDE_DOWN) {
          action.dismiss()
          this.closeHomeSheet()
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

  immersiveCallback = (sharableTarget: harmonyShare.SharableTarget) => {
    if (AppManager.uiState.selected) {
      let config: ConfigJson | undefined = AppManager.easytier.getConfig(AppManager.uiState.selected)
      if (config) {
        buildShareData(config, (data) => {
          sharableTarget.share(data);
        }, false, AppManager.easytier.getConfigName(AppManager.uiState.selected))
      }
    } else {
      sendToast("先选择一个实例，再分享吧")
    }
  }
}
