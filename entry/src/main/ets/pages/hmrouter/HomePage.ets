import { HMRouter, HMRouterMgr } from '@hadss/hmrouter';
import { deviceInfo, emitter } from '@kit.BasicServicesKit';
import { HdsNavigation, HdsNavigationTitleMode, TitleBarStyleOptions } from '@hms.hds.hdsBaseComponent';
import { ColorMetrics, LengthMetrics } from '@kit.ArkUI';
import { AppManager } from '../../AppManager';
import { startupMark } from '../../services/runtime/StartupTrace';
import { EventHelper } from '../../util/EventHelper';
import { HomeSheetContentBuilder } from '../../components/sheet/HomeSheet';
import { setConfigName } from '../../components/sheet/NewConfig';
import { ActionBarButton, ActionBarStyle, HdsActionBar, hdsMaterial } from '@kit.UIDesignKit';
import { sendToast } from '../../ToastUtil';
import { BottomAnimator } from '../../class/animator/BottomAnimator';
import { harmonyShare } from '@kit.ShareKit';
import { WindowUtil } from '../../WindowUtil';
import { buildShareData, buildShareUrlSync } from '../../util/ShareUtil';
import { ConfigJson } from '../../config/schema/SchemaConfig';
import { generateBarcode, scanCore } from '@kit.ScanKit';
import { image } from '@kit.ImageKit';
import { QRDialog } from '../../components/util/QRImage';
import { Favorite } from '../../components/index/Favorite';
import { Instances } from '../../components/index/Instances';
import { Logs as HomeLogsCard } from '../../components/index/Logs';
import { QQGroups } from '../../components/index/QQGroups';
import { RemoteControl } from '../../components/index/RemoteControl';
import { HdsMenuButton } from '../Components';
import { CompSizeWithPos, DesktopLayout, LayoutUtil } from '../../components/layout/desktop/DesktopGridLayout';
import { APP_BUNDLE_NAME, ENTRY_FORM_ABILITY_NAME, ENTRY_MODULE_NAME } from '../../services/runtime/AbilityRuntimePolicy';
import { ChangelogPresentationService } from '../../services/changelog/ChangelogPresentationService';
import { Logger } from '../../shared/logging/Logger';
import { EasyTierProRecommendationDialog } from '../../components/util/EasyTierProRecommendationDialog';
import { EasyTierProPromotionService } from '../../services/easytier/EasyTierProPromotionService';

const HOME_CARD_TYPES: string[] = ['Instances', 'Logs', 'Favorite', 'RemoteControl', 'QQ']
const HOME_DEFAULT_CARD_SEQUENCE: CompSizeWithPos[] = [
  { type: 'Instances', x: 0, y: 0, width: 2, height: 1 },
  { type: 'Logs', x: 2, y: 0, width: 2, height: 1 },
  { type: 'Favorite', x: 4, y: 0, width: 2, height: 1 },
  { type: 'RemoteControl', x: 0, y: 1, width: 2, height: 1 },
  { type: 'QQ', x: 2, y: 1, width: 2, height: 1 }
]

@Builder
function buildHomeComp(type: string) {
  if (type === 'Instances') {
    Instances()
  } else if (type === 'Logs') {
    HomeLogsCard()
  } else if (type === 'Favorite') {
    Favorite()
  } else if (type === 'RemoteControl') {
    RemoteControl()
  } else if (type === 'QQ') {
    QQGroups()
  } else {
    Text(type)
      .fontSize(18)
      .fontWeight(FontWeight.Bold)
      .fontColor($r('sys.color.font_primary'))
  }
}

@HMRouter({ pageUrl: "HomePage" })
@ComponentV2
export struct HomePage {
  scroller: Scroller = new Scroller();
  @Local sheet: boolean = false
  @Local sheet_type: string = ""
  private qrPixelMap: image.PixelMap | undefined = undefined
  private qrDialogController: CustomDialogController | null = null
  private proRecommendationDialogController: CustomDialogController | null = null
  private active: boolean = false
  private startupPresentationGeneration: number = 0
  private qrRequestId: number = 0
  private homeOpenSheetCallback = (data: emitter.EventData) => {
    this.sheet_type = data.data!.type as string
    this.sheet = true
  }
  private homeCloseSheetCallback = () => {
    this.closeHomeSheet()
  }

  private closeHomeSheet(): void {
    if (this.sheet_type === 'new') {
      setConfigName(undefined)
    }
    this.sheet = false
    this.sheet_type = ''
  }

  aboutToAppear(): void {
    startupMark('home.aboutToAppear')
    this.active = true
    const generation = ++this.startupPresentationGeneration
    EventHelper.emitterListener("home_open_sheet", this.homeOpenSheetCallback)
    EventHelper.emitterListener("home_close_sheet", this.homeCloseSheetCallback)
    harmonyShare.on('knockShare', this.immersiveCallback);
    AppManager.init(this.getUIContext()).then(() => {
      if (!this.active || generation !== this.startupPresentationGeneration) {
        return
      }
      this.presentStartupPage()
    }).catch((error: Error) => {
      Logger.error(`startup presentation init failed: ${JSON.stringify(error)}`, 'HomePage')
    })
  }

  private presentStartupPage(): void {
    if (AppManager.uiState.help2) {
      AppManager.preference.completeInitialTutorial()
      HMRouterMgr.to("HelpPage")
        .onResult(() => this.presentAfterTutorial())
        .push()
      return
    }
    this.presentAfterTutorial()
  }

  private presentAfterTutorial(): void {
    if (ChangelogPresentationService.consumeCurrentVersion()) {
      HMRouterMgr.to('ChangelogPage')
        .onResult(() => this.presentEasyTierProRecommendation())
        .push()
      return
    }
    this.presentEasyTierProRecommendation()
  }

  private presentEasyTierProRecommendation(): void {
    if (this.proRecommendationDialogController || !EasyTierProPromotionService.consumeFirstPresentation()) {
      return
    }
    const controller = new CustomDialogController({
      builder: EasyTierProRecommendationDialog({
        onOpen: () => {
          this.closeProRecommendationDialog()
          EasyTierProPromotionService.openAppGallery(this.getUIContext())
        },
        onDismiss: () => {
          this.closeProRecommendationDialog()
        }
      }),
      autoCancel: true,
      alignment: DialogAlignment.Center,
      customStyle: true,
      isModal: true,
      maskColor: 'rgba(0,0,0,0.35)',
      cancel: () => {
        if (this.proRecommendationDialogController === controller) {
          this.proRecommendationDialogController = null
        }
      }
    })
    this.proRecommendationDialogController = controller
    controller.open()
  }

  aboutToDisappear(): void {
    this.active = false
    this.startupPresentationGeneration += 1
    this.closeQrDialog()
    this.closeProRecommendationDialog()
    EventHelper.emitterOff("home_open_sheet", this.homeOpenSheetCallback)
    EventHelper.emitterOff("home_close_sheet", this.homeCloseSheetCallback)
    harmonyShare.off('knockShare', this.immersiveCallback);
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

  private closeProRecommendationDialog(): void {
    const controller = this.proRecommendationDialogController
    this.proRecommendationDialogController = null
    if (controller) {
      try {
        controller.close()
      } catch (_) {
      }
    }
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

  async startAndStop(): Promise<void> {
    if (AppManager.easytier.runningNetworks.size > 0) {
      await AppManager.easytier.stopAndWait()
    } else {
      await AppManager.easytier.startAfterStop()
    }
  }

  status(): void {
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

  private versionText(): string {
    return "v" + AppManager.easytier.version().split("-")[0]
  }

  private openNewSheet(): void {
    AppManager.permission.requestDistributePerm(false).then(() => {
      this.sheet_type = "new"
      this.sheet = true
    })
  }

  private openSettingSheet(): void {
    this.sheet_type = "setting"
    this.sheet = true
  }

  private homeDefaultCardSequence(): CompSizeWithPos[] {
    return HOME_DEFAULT_CARD_SEQUENCE.map((item: CompSizeWithPos) => {
      return {
        type: item.type,
        x: item.x,
        y: item.y,
        width: item.width,
        height: item.height
      } as CompSizeWithPos
    })
  }

  private normalizeHomeCardType(type: string): string {
    return type === 'SharedPeers' ? 'RemoteControl' : type
  }

  private homeCardSequence(): CompSizeWithPos[] {
    const hasLegacyControlCard = AppManager.uiState.raw_comp_sequence.split('|').some((value: string) => {
      return value.split('_')[0] === 'Control'
    })
    if (hasLegacyControlCard) {
      return this.homeDefaultCardSequence()
    }
    if (AppManager.uiState.raw_comp_sequence.length === 0) {
      return []
    }
    const parsed: CompSizeWithPos[] = []
    const seen: string[] = []
    AppManager.uiState.raw_comp_sequence.split('|').forEach((value: string) => {
      const raw = value.split('_')
      if (raw.length < 5) {
        return
      }
      const type = this.normalizeHomeCardType(raw[0])
      if (!HOME_CARD_TYPES.includes(type) || seen.includes(type)) {
        return
      }
      const x = Number.parseInt(raw[1])
      const y = Number.parseInt(raw[2])
      const width = Number.parseInt(raw[3])
      const height = Number.parseInt(raw[4])
      if (Number.isNaN(x) || Number.isNaN(y) || Number.isNaN(width) || Number.isNaN(height)) {
        return
      }
      seen.push(type)
      parsed.push({
        type: type,
        x: x,
        y: y,
        width: width,
        height: height
      } as CompSizeWithPos)
    })
    return parsed.length > 0 ? parsed : this.homeDefaultCardSequence()
  }

  private saveHomeCardSequence(layout: LayoutUtil): void {
    let sequenceData = ''
    layout.comp_sequence.forEach((type: string) => {
      const size = layout.getCompSize(type)
      sequenceData += `${type}_${size.grid_x}_${size.grid_y}_${size.lane_w}_${size.lane_h}|`
    })
    AppManager.preference.updateSequence(sequenceData.length > 0 ?
      sequenceData.substring(0, sequenceData.length - 1) :
      sequenceData)
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
            void this.qr()
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
          backgroundColor: ColorMetrics.resourceColor($r('sys.color.interactive_select'))
        }),
        isExpand: AppManager.easytier.runningNetworks.size > 0
      })
    }
    .alignItems(HorizontalAlign.Center)
    .justifyContent(FlexAlign.End)
    .height('100%')
    .width('100%')
    .hitTestBehavior(HitTestMode.Transparent)
    .padding({ left: 20, right: 20 })
  }

  @Builder
  content() {
    Scroll(this.scroller) {
      Column() {
        Column()
          .width('100%')
          .height(138)

        DesktopLayout({
          comp_sequence: this.homeCardSequence(),
          types: HOME_CARD_TYPES,
          saveSequence: (layout: LayoutUtil): void => {
            this.saveHomeCardSequence(layout)
          },
          contentBuilder: wrapBuilder(buildHomeComp),
          name: 'home',
          hasWidgetList: ['Favorite'],
          formWantFunc: (comp_type: string) => {
            return {
              bundleName: APP_BUNDLE_NAME,
              abilityName: ENTRY_FORM_ABILITY_NAME,
              parameters: {
                'ohos.extra.param.key.form_dimension': 1,
                'ohos.extra.param.key.form_name': comp_type.toLowerCase() + '_widget',
                'ohos.extra.param.key.module_name': ENTRY_MODULE_NAME
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
    .edgeEffect(EdgeEffect.Spring)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
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
    } else {
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
    .bindToScrollable([this.scroller])
    .height('100%')
    .width('100%')
    .titleBar({
      style: this.navTitleStyle(),
      content: {
        title: {
          mainTitle: "EasyTier",
          subTitle: this.versionText()
        },
        menu: {
          value: [
            HdsMenuButton("new", $r("sys.symbol.plus"), () => {
              this.openNewSheet()
            }),
            HdsMenuButton("setting", $r("sys.symbol.gearshape"), () => {
              this.openSettingSheet()
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
