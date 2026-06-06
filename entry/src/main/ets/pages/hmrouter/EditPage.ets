import { HMRouter, HMRouterMgr } from '@hadss/hmrouter'
import { deviceInfo } from '@kit.BasicServicesKit'
import { HdsNavigation, HdsNavigationTitleMode,
  hdsMaterial,
  TitleBarStyleOptions} from '@kit.UIDesignKit'
import { ComponentContent, LengthMetrics } from '@kit.ArkUI'
import { AppManager } from '../../AppManager'
import { HdsMenuButton } from '../Components'
import { SheetContentBuilder } from '../../components/sheet/Basic'
import { EventHelper } from '../../util/EventHelper'
import { WindowUtil } from '../../WindowUtil'
import { harmonyShare, systemShare } from '@kit.ShareKit'
import { Logger } from '../../shared/logging/Logger'
import { common } from '@kit.AbilityKit'
import { buildShareData, buildShareUrl, buildTomlShareData } from '../../util/ShareUtil'
import { EditPageParam } from '../../types/navigation/PageParam'
import { ConfigJson } from '../../config/schema/SchemaConfig'
import {
  clearEditingConfigCache,
  ensureEditingFieldsAsync,
  prepareEditingConfig
} from '../../services/config/storage/StoredConfigService'
import { generateBarcode, scanCore } from '@kit.ScanKit'
import { image } from '@kit.ImageKit'
import { DialogHub, DialogMode } from '@hadss/dialoghub'
import { dlpAntiPeep } from '@kit.DeviceSecurityKit';
import { QRImage } from '../../components/util/QRImage'
import { buildEditRenderPlan, emptyEditRenderPlan } from '../../config/render/EditRenderResolver'
import { EditRenderPlan, EditSectionRenderPlan } from '../../config/render/EditRenderNode'
import { EditSectionView } from '../../components/edit/EditSectionView'

@Builder
function ShareMenu() {
  Menu() {
    MenuItem({content: "分享直达链接"}).onClick(() => {
      const editingId = AppManager.uiState.editingInstance
      let config: ConfigJson | undefined = editingId ? AppManager.easytier.getConfig(editingId) : undefined
      if (config) {
        buildShareData(config, (data) => {
          let controller: systemShare.ShareController = new systemShare.ShareController(data);
          let uiContext: UIContext = AppManager.content.uiContext!;
          let context: common.UIAbilityContext = uiContext.getHostContext() as common.UIAbilityContext;
          controller.show(context, {
            selectionMode: systemShare.SelectionMode.SINGLE,
            previewMode: systemShare.SharePreviewMode.DEFAULT,
            excludedAbilities: [systemShare.ShareAbilityType.PRINT,
              systemShare.ShareAbilityType.SAVE_TO_SUPERHUB]
          }).catch(() => {
            Logger.error(`[Index] systemShareConfig::An unexpected error occurred.`);
          })
        })
      }
    })
    MenuItem({content: "扫码直达"}).onClick(() => {
      const editingId = AppManager.uiState.editingInstance
      let config: ConfigJson | undefined = editingId ? AppManager.easytier.getConfig(editingId) : undefined
      if (config) {
        buildShareUrl(config, (content) => {
          let options: generateBarcode.CreateOptions = {
            scanType: scanCore.ScanType.QR_CODE,
            height: 400,
            width: 400
          }
          try {
            generateBarcode.createBarcode(content, options).then((pixelMap: image.PixelMap) => {
              DialogHub.getCustomDialog()
                .setOperableContent(wrapBuilder(QRImage), () => {
                  return pixelMap
                })
                .setStyle({
                  radius: 18,
                })
                .setConfig({ dialogBehavior: { isModal: true, autoDismiss: true, passThroughGesture: false }, dialogMode: DialogMode.CUSTOM_DIALOG })
                .build()
                .show();
            }).catch((error: BusinessError) => {})
          } catch (error) {}
        }, true)
      }
    })
    MenuItem({content: "分享Toml文件"}).onClick(() => {
      const editingId = AppManager.uiState.editingInstance
      let config: ConfigJson | undefined = editingId ? AppManager.easytier.getConfig(editingId) : undefined
      if (config) {
        const configName: string | undefined = AppManager.easytier.getConfigName(config.instance_id)
        buildTomlShareData(config, (data) => {
          let controller: systemShare.ShareController = new systemShare.ShareController(data);
          let uiContext: UIContext = AppManager.content.uiContext!;
          let context: common.UIAbilityContext = uiContext.getHostContext() as common.UIAbilityContext;
          controller.show(context, {
            selectionMode: systemShare.SelectionMode.SINGLE,
            previewMode: systemShare.SharePreviewMode.DEFAULT,
            excludedAbilities: [systemShare.ShareAbilityType.PRINT,
              systemShare.ShareAbilityType.SAVE_TO_SUPERHUB]
          }).catch(() => {
            Logger.error(`[Index] systemShareConfig::An unexpected error occurred.`);
          })
        }, configName)
      }
    })
  }
}

@HMRouter({ pageUrl: "EditPage" })
@ComponentV2
export struct EditPage {
  @Local uuid: string | undefined;
  @Provider("unsafe_status") unsafe: boolean = false
  @Provider("peep_masked") peepMasked: boolean = false
  @Provider("peep_dismissed") peepDismissed: boolean = false
  @Local sheet: boolean = false
  @Local sheet_type: string = ""
  @Local share_menu_id: string = "share_menu_id"
  @Local editingConfigReady: boolean = false
  @Local titleText: string = ""
  @Local activePageIndex: number = 0
  private renderPlan: EditRenderPlan = emptyEditRenderPlan()
  private active: boolean = false
  private dlpRegistered: boolean = false
  private loadedSectionKeys: Set<string> = new Set()
  private loadingSectionKeys: Set<string> = new Set()
  private sectionLoadQueue: number[] = []
  private sectionLoadBusy: boolean = false
  private sectionLoadTimer: number = -1
  private sectionPreloadTimer: number = -1
  private sectionPreloadQueued: boolean = false

  private refreshTitle(): void {
    this.titleText = AppManager.easytier.getConfigLabel(this.uuid, this.uuid ?? '')
  }

  @Computed
  get name() {
    if (this.uuid) {
      return AppManager.easytier.getConfigName(this.uuid)
    }
    return ""
  }

  private onStatusChange = async (status: dlpAntiPeep.DlpAntiPeepStatus): Promise<void> => {
    if (status === dlpAntiPeep.DlpAntiPeepStatus.PASS) {
      this.unsafe = false;
    } else if (status === dlpAntiPeep.DlpAntiPeepStatus.HIDE) {
      this.unsafe = true;
      if (!this.peepDismissed) {
        this.peepMasked = true;
      }
    }
  }

  private resetSectionLoading(): void {
    this.loadedSectionKeys.clear()
    this.loadingSectionKeys.clear()
    this.sectionLoadQueue = []
    this.sectionLoadBusy = false
    this.sectionPreloadQueued = false
    if (this.sectionLoadTimer >= 0) {
      clearTimeout(this.sectionLoadTimer)
      this.sectionLoadTimer = -1
    }
    if (this.sectionPreloadTimer >= 0) {
      clearTimeout(this.sectionPreloadTimer)
      this.sectionPreloadTimer = -1
    }
  }

  private isValidSectionIndex(index: number): boolean {
    return index >= 0 && index < this.renderPlan.sections.length
  }

  private isSectionQueued(index: number): boolean {
    return this.sectionLoadQueue.indexOf(index) >= 0
  }

  private enqueueSectionLoad(index: number, highPriority: boolean = false, delayMs: number = 0): void {
    if (!this.isValidSectionIndex(index)) {
      return
    }
    const section = this.renderPlan.sections[index]
    if (this.loadedSectionKeys.has(section.key) || this.loadingSectionKeys.has(section.key) || this.isSectionQueued(index)) {
      return
    }
    if (highPriority) {
      this.sectionLoadQueue.unshift(index)
    } else {
      this.sectionLoadQueue.push(index)
    }
    this.scheduleSectionLoadDrain(delayMs)
  }

  private scheduleSectionLoadDrain(delayMs: number = 0): void {
    if (!this.active || this.sectionLoadBusy || this.sectionLoadQueue.length === 0) {
      return
    }
    if (this.sectionLoadTimer >= 0) {
      clearTimeout(this.sectionLoadTimer)
      this.sectionLoadTimer = -1
    }
    this.sectionLoadTimer = setTimeout(() => {
      this.sectionLoadTimer = -1
      this.drainSectionLoadQueue()
    }, delayMs)
  }

  private takeNextSectionIndex(): number {
    while (this.sectionLoadQueue.length > 0) {
      const index = this.sectionLoadQueue.shift() as number
      if (!this.isValidSectionIndex(index)) {
        continue
      }
      const section = this.renderPlan.sections[index]
      if (!this.loadedSectionKeys.has(section.key) && !this.loadingSectionKeys.has(section.key)) {
        return index
      }
    }
    return -1
  }

  private drainSectionLoadQueue(): void {
    if (!this.active || this.sectionLoadBusy) {
      return
    }
    const index = this.takeNextSectionIndex()
    if (index < 0) {
      return
    }
    const section = this.renderPlan.sections[index]
    this.sectionLoadBusy = true
    this.loadingSectionKeys.add(section.key)
    ensureEditingFieldsAsync(this.uuid, section.topLevelFields).then(() => {
      this.loadedSectionKeys.add(section.key)
      if (index === 0) {
        this.scheduleTrailingSectionPreload()
      }
    }).catch(() => {
    }).finally(() => {
      this.loadingSectionKeys.delete(section.key)
      this.sectionLoadBusy = false
      if (this.active && this.sectionLoadQueue.length > 0) {
        this.scheduleSectionLoadDrain(120)
      }
    })
  }

  private scheduleTrailingSectionPreload(): void {
    if (this.sectionPreloadQueued) {
      return
    }
    this.sectionPreloadQueued = true
    this.sectionPreloadTimer = setTimeout(() => {
      this.sectionPreloadTimer = -1
      if (!this.active) {
        return
      }
      this.enqueueSectionLoad(this.activePageIndex, true)
      for (let index = 1; index < this.renderPlan.sections.length; index++) {
        this.enqueueSectionLoad(index, false)
      }
    }, 180)
  }

  aboutToAppear(): void {
    this.active = true
    let param = HMRouterMgr.getCurrentParam() as EditPageParam;
    this.uuid = param.uuid
    this.unsafe = param.unsafe
    this.refreshTitle()
    AppManager.uiState.editingInstance = this.uuid
    this.activePageIndex = 0
    this.resetSectionLoading()
    prepareEditingConfig(this.uuid)
    this.renderPlan = buildEditRenderPlan()
    this.editingConfigReady = true
    this.enqueueSectionLoad(0, true, 32)
    EventHelper.emitterListener("edit_open_sheet", (data) => {
      this.sheet_type = data.data!.type as string
      this.sheet = true
    })
    EventHelper.emitterListener("edit_close_sheet", () => {
      this.sheet = false
      this.refreshTitle()
    })
    harmonyShare.on('knockShare', this.immersiveCallback);
    harmonyShare.on('gesturesShare', this.immersiveCallback);
    setTimeout(() => {
      this.initDlpAntiPeep()
    }, 0)
  }

  private async initDlpAntiPeep(): Promise<void> {
    if (canIUse("SystemCapability.Security.DlpAntiPeep")) {
      try {
        const isOpen = await dlpAntiPeep.isDlpAntiPeepSwitchOn();
        if (!this.active) {
          return
        }
        if (isOpen) {
          dlpAntiPeep.on('dlpAntiPeep', this.onStatusChange);
          this.dlpRegistered = true
        } else if (!AppManager.uiState.ask_dlp) {
          AppManager.uiState.ask_dlp = true
          const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
          const result = await dlpAntiPeep.requestAntiPeepOptions(context);
          if (!this.active) {
            return
          }
          if (result === dlpAntiPeep.AntiPeepOptionsResult.SUCCESS ||
            result === dlpAntiPeep.AntiPeepOptionsResult.ALREADY_ON) {
            dlpAntiPeep.on('dlpAntiPeep', this.onStatusChange);
            this.dlpRegistered = true
          }
        }
      } catch (error) {
        console.error(`Failed to init DlpAntiPeep. Code: ${error.code}, message: ${error.message}`);
      }
    }
  }

  aboutToDisappear(): void {
    this.active = false
    this.resetSectionLoading()
    EventHelper.emitterOff("edit_open_sheet")
    EventHelper.emitterOff("edit_close_sheet")
    harmonyShare.off('knockShare', this.immersiveCallback);
    if (deviceInfo.sdkApiVersion >= 20) {
      harmonyShare.off('gesturesShare', this.immersiveCallback);
    }
    AppManager.uiState.editingInstance = undefined
    clearEditingConfigCache(this.uuid)
    if (this.dlpRegistered && canIUse("SystemCapability.Security.DlpAntiPeep")) {
      try {
        dlpAntiPeep.off('dlpAntiPeep', this.onStatusChange);
        this.dlpRegistered = false
      } catch (error) {
        console.error(`Failed to off DlpAntiPeep. Code: ${error.code}, message: ${error.message}`);
      }
    }
  }

  @Builder
  pageContent(section: EditSectionRenderPlan, index: number) {
    Column() {
      EditSectionView({ section: section })
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  content() {
    Swiper() {
      ForEach(this.renderPlan.sections, (section: EditSectionRenderPlan, index: number) => {
        this.pageContent(section, index)
      }, (section: EditSectionRenderPlan) => section.key)
    }
    .width('100%')
    .height('100%')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .id("edit_content")
    .displayCount(WindowUtil.uiType / 2)
    .cachedCount(0, false)
    .loop(false)
    .indicator(DotIndicator.dot().top(46))
    .onAnimationStart((index: number, targetIndex: number) => {
      this.enqueueSectionLoad(targetIndex, true)
    })
    .onAnimationEnd((index: number) => {
      this.activePageIndex = index
      this.enqueueSectionLoad(index, true)
    })
  }

  @Builder
  loadingContent() {
    Column({ space: 12 }) {
      LoadingProgress()
        .width(36)
        .height(36)
      Text('正在加载配置')
        .fontSize(14)
        .fontColor($r('sys.color.font_secondary'))
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
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
      if (this.editingConfigReady && this.renderPlan.sections.length > 0) {
        this.content()
      } else {
        this.loadingContent()
      }
    }
    .titleBar({
      style: this.navTitleStyle(),
      content: {
        title: {
          mainTitle: this.titleText,
          subTitle: this.uuid!
        },
        menu: {
          value: [
            HdsMenuButton($r("app.string.i18_favorite"),
              AppManager.data.isFavorite(this.uuid!) ? $r("sys.symbol.star_fill") : $r("sys.symbol.star"), () => {
                AppManager.data.changeFavorite(this.uuid!)
              }),
            HdsMenuButton($r("app.string.i18_share"), $r("sys.symbol.rectangle_and_arrowshape_turn_up_right_fill"),
              async () => {
                let uiContext = this.getUIContext();
                let promptAction = uiContext.getPromptAction();
                let contentNode = new ComponentContent(uiContext, wrapBuilder(ShareMenu));
                promptAction.openMenu(
                  contentNode,
                  { id: this.share_menu_id }
                ).catch(() => {})
              }, this.share_menu_id),
            HdsMenuButton($r("app.string.i18_delete"), $r("sys.symbol.trash"), () => {
              HMRouterMgr.pop()
              AppManager.data.delConfig(this.uuid!)
            }),
            HdsMenuButton($r("app.string.i18_rename"), $r("sys.symbol.pencil_line_1"), () => {
              EventHelper.emitterPublish("edit_open_sheet", {
                data: {
                  type: "rename"
                }
              })
            })
          ]
        }
      }
    })
    .mode(NavigationMode.Stack)
    .titleMode(HdsNavigationTitleMode.MINI)
    .hideBackButton(false)
    .hideTitleBar(false)
    .backgroundColor($r('sys.color.background_secondary'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .bindSheet(this.sheet, SheetContentBuilder(this.sheet_type), {
      height: SheetSize.MEDIUM,
      preferType: SheetType.CENTER,
      showClose: false,
      dragBar: false,
      blurStyle: BlurStyle.Thin,
      onWillDismiss: (action) => {
        if (action.reason != DismissReason.SLIDE_DOWN) {
          action.dismiss()
          this.sheet = false
        }
      }
    })
  }

  immersiveCallback = (sharableTarget: harmonyShare.SharableTarget) => {
    let config: ConfigJson | undefined = this.uuid ? AppManager.easytier.getConfig(this.uuid) : undefined
    if (config) {
      buildShareData(config, (data) => {
        sharableTarget.share(data);
      }, false, this.name, this.uuid)
    }
  }
}
