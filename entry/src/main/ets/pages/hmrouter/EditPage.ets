import { ConfigField, configFieldRegistry } from '../../config/fields/ConfigFieldRegistry'
import { FieldEdit } from '../../components/edit/FieldEdit'
import { HMRouter, HMRouterMgr } from '@hadss/hmrouter'
import { deviceInfo } from '@kit.BasicServicesKit'
import { HdsNavigation, HdsNavigationTitleMode, ScrollEffectType, HdsNavigationAttribute,
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
import { clearEditingConfigCache, refreshEditingConfig } from '../../services/config/storage/StoredConfigService'
import { generateBarcode, scanCore } from '@kit.ScanKit'
import { image } from '@kit.ImageKit'
import { DialogHub, DialogMode } from '@hadss/dialoghub'
import { dlpAntiPeep } from '@kit.DeviceSecurityKit';
import { QRImage } from '../../components/util/QRImage'

@Builder
function ShareMenu() {
  Menu() {
    MenuItem({content: "分享直达链接"}).onClick(() => {
      let config: ConfigJson | undefined = AppManager.easytier.getEditingConfig()
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
      let config: ConfigJson | undefined = AppManager.easytier.getEditingConfig()
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
      let config: ConfigJson | undefined = AppManager.easytier.getEditingConfig()
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
  @Local loadedFlagPage: boolean = false
  @Local loadedAdvancedPage: boolean = false
  @Local loadedOtherPage: boolean = false
  private active: boolean = false
  private dlpRegistered: boolean = false

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

  aboutToAppear(): void {
    this.active = true
    let param = HMRouterMgr.getCurrentParam() as EditPageParam;
    this.uuid = param.uuid
    this.unsafe = param.unsafe
    this.ensureVisiblePagesLoaded(0)
    refreshEditingConfig(this.uuid)
    EventHelper.emitterListener("edit_open_sheet", (data) => {
      this.sheet_type = data.data!.type as string
      this.sheet = true
    })
    EventHelper.emitterListener("edit_close_sheet", () => {
      this.sheet = false
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
    this.loadedFlagPage = false
    this.loadedAdvancedPage = false
    this.loadedOtherPage = false
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

  private visiblePageCount(): number {
    return Math.max(1, Math.trunc(WindowUtil.uiType / 2))
  }

  private ensureVisiblePagesLoaded(index: number): void {
    const lastVisiblePage = Math.min(3, index + this.visiblePageCount() - 1)
    for (let page = index; page <= lastVisiblePage; page++) {
      if (page === 1) {
        this.loadedFlagPage = true
      } else if (page === 2) {
        this.loadedAdvancedPage = true
      } else if (page === 3) {
        this.loadedOtherPage = true
      }
    }
  }

  @Builder
  content() {
    Swiper() {
      List({ space: 20 }) {
        ListItem()
          .width('100%')
          .height(56)
        ForEach(configFieldRegistry.basicFields, (field: ConfigField) => {
          ListItem() {
            FieldEdit({ field: field })
              .width('100%')
          }
        })
        ListItem()
          .width('100%')
          .height(150)
      }
      .width('100%')
      .height('100%')
      .scrollBar(BarState.Off)
      .chainAnimation(true)
      .edgeEffect(EdgeEffect.None)
      .padding({ left: 20, right: 20 })
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

      if (this.loadedFlagPage) {
        Scroll() {
          Column({ space: 20 }) {
            if (deviceInfo.sdkApiVersion >= 20) {
              Row()
                .width('100%')
                .height(56)
            }
            FieldEdit({ field: configFieldRegistry.flagField })
              .width('100%')
            Row()
              .width('100%')
              .height(150)
          }
        }
        .width('100%')
        .height('100%')
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.None)
        .padding({ left: 20, right: 20 })
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      } else {
        Column().width('100%').height('100%')
      }

      if (this.loadedAdvancedPage) {
        List({ space: 20 }) {
          if (deviceInfo.sdkApiVersion >= 20) {
            ListItem()
              .width('100%')
              .height(56)
          }
          ForEach(configFieldRegistry.advancedFields, (field: ConfigField) => {
            ListItem() {
              FieldEdit({ field: field })
                .width('100%')
            }
          })
          ListItem()
            .width('100%')
            .height(150)
        }
        .width('100%')
        .height('100%')
        .scrollBar(BarState.Off)
        .chainAnimation(true)
        .edgeEffect(EdgeEffect.None)
        .padding({ left: 20, right: 20 })
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      } else {
        Column().width('100%').height('100%')
      }

      if (this.loadedOtherPage) {
        List({ space: 20 }) {
          if (deviceInfo.sdkApiVersion >= 20) {
            ListItem()
              .width('100%')
              .height(56)
          }
          ForEach(configFieldRegistry.otherFields, (field: ConfigField) => {
            ListItem() {
              FieldEdit({ field: field })
                .width('100%')
            }
          })
          ListItem()
            .width('100%')
            .height(150)
        }
        .width('100%')
        .height('100%')
        .scrollBar(BarState.Off)
        .chainAnimation(true)
        .edgeEffect(EdgeEffect.None)
        .padding({ left: 20, right: 20 })
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      } else {
        Column().width('100%').height('100%')
      }
    }
    .width('100%')
    .height('100%')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .id("edit_content")
    .displayCount(WindowUtil.uiType / 2)
    .loop(false)
    .indicator(DotIndicator.dot().top(46))
    .onChange((index: number) => {
      this.ensureVisiblePagesLoaded(index)
    })
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
    .titleBar({
      style: this.navTitleStyle(),
      content: {
        title: {
          mainTitle: this.name!,
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
