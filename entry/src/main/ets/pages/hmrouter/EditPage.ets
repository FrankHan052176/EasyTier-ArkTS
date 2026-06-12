import { HMRouter, HMRouterMgr } from '@hadss/hmrouter'
import { deviceInfo, emitter } from '@kit.BasicServicesKit'
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
import { buildShareData, buildShareUrlSync, buildTomlShareData } from '../../util/ShareUtil'
import { EditPageParam } from '../../types/navigation/PageParam'
import { ConfigJson } from '../../config/schema/SchemaConfig'
import {
  clearEditingConfigCache,
  ensureEditingFieldsAsync,
  getStoredConfigLabel,
  getStoredConfigName,
  prepareEditingConfig,
  resetEditingConfigStoreRef,
  setEditingConfigStoreRef
} from '../../services/config/storage/StoredConfigService'
import { generateBarcode, scanCore } from '@kit.ScanKit'
import { image } from '@kit.ImageKit'
import { dlpAntiPeep } from '@kit.DeviceSecurityKit';
import { QRDialog } from '../../components/util/QRImage'
import { buildEditRenderPlan, emptyEditRenderPlan } from '../../config/render/EditRenderResolver'
import { EditRenderPlan, EditSectionRenderPlan } from '../../config/render/EditRenderNode'
import { EditSectionView } from '../../components/edit/EditSectionView'
import { clearEditValue } from '../../class/config/Basic'
import { MemoryDiagnosticsService } from '../../services/runtime/MemoryDiagnosticsService'
import { RemoteManageService } from '../../services/remote/RemoteManageService'
import { sendToast } from '../../ToastUtil'

class ShareMenuParam {
  onQrClick: () => void

  constructor(onQrClick: () => void) {
    this.onQrClick = onQrClick
  }
}

@Builder
function ShareMenu(param: ShareMenuParam) {
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
      param.onQrClick()
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
  @Local remoteEditing: boolean = false
  @Local remoteDeviceName: string = ""
  @Local remoteSessionId: string = ""
  @Local activePageIndex: number = 0
  @Local animationTargetIndex: number = -1
  private qrPixelMap: image.PixelMap | undefined = undefined
  private qrDialogController: CustomDialogController | null = null
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
  private sectionLoadGeneration: number = 0
  private sectionLoadFailureCounts: Map<string, number> = new Map()
  private gesturesShareRegistered: boolean = false
  private knockShareRegistered: boolean = false
  private shareMenuContent: ComponentContent<Object> | undefined = undefined
  private qrRequestId: number = 0
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

  @Computed
  get name() {
    if (this.uuid) {
      return getStoredConfigName(this.uuid) ?? ''
    }
    return ""
  }

  aboutToAppear(): void {
    this.active = true
    if (AppManager.uiState.debug_log) {
      MemoryDiagnosticsService.watchObject(this, 'EditPage')
      MemoryDiagnosticsService.markDelayed('EditPage.aboutToAppear')
    }
    let param = HMRouterMgr.getCurrentParam() as EditPageParam;
    this.uuid = param.uuid
    this.unsafe = param.unsafe
    this.remoteEditing = param.source === 'remote'
    this.remoteDeviceName = param.remoteDeviceName ?? ''
    this.remoteSessionId = param.remoteSessionId ?? ''
    if (this.remoteEditing && (!this.remoteSessionId || !RemoteManageService.isCurrentSession(this.remoteSessionId))) {
      this.active = false
      sendToast('远端连接已变化，请重新进入编辑', $r('sys.symbol.exclamationmark_circle'), 1)
      setTimeout(() => {
        HMRouterMgr.pop()
      }, 0)
      return
    }
    setEditingConfigStoreRef(this.remoteEditing ? {
      source: 'remote',
      remoteSessionId: this.remoteSessionId,
      remoteDeviceName: param.remoteDeviceName
    } : {
      source: 'local'
    })
    this.refreshTitle()
    AppManager.uiState.editingInstance = this.uuid
    this.activePageIndex = 0
    this.animationTargetIndex = -1
    this.resetSectionLoading()
    prepareEditingConfig(this.uuid)
    this.renderPlan = buildEditRenderPlan()
    this.editingConfigReady = true
    this.enqueueSectionLoad(0, true, 32)
    EventHelper.emitterListener("edit_open_sheet", this.editOpenSheetCallback)
    EventHelper.emitterListener("edit_close_sheet", this.editCloseSheetCallback)
    if (!this.remoteEditing) {
      harmonyShare.on('knockShare', this.immersiveCallback);
      this.knockShareRegistered = true
    }
    if (!this.remoteEditing && deviceInfo.sdkApiVersion >= 20) {
      harmonyShare.on('gesturesShare', this.immersiveCallback);
      this.gesturesShareRegistered = true
    }
    setTimeout(() => {
      this.initDlpAntiPeep()
    }, 0)
  }

  aboutToDisappear(): void {
    if (AppManager.uiState.debug_log) {
      MemoryDiagnosticsService.markDelayed('EditPage.aboutToDisappear')
    }
    this.active = false
    this.closeShareMenu()
    this.closeQrDialog()
    this.clearSheetState()
    this.resetSectionLoading()
    EventHelper.emitterOff("edit_open_sheet", this.editOpenSheetCallback)
    EventHelper.emitterOff("edit_close_sheet", this.editCloseSheetCallback)
    if (this.knockShareRegistered) {
      harmonyShare.off('knockShare', this.immersiveCallback);
      this.knockShareRegistered = false
    }
    if (this.gesturesShareRegistered) {
      harmonyShare.off('gesturesShare', this.immersiveCallback);
      this.gesturesShareRegistered = false
    }
    AppManager.uiState.editingInstance = undefined
    clearEditingConfigCache(this.uuid)
    resetEditingConfigStoreRef()
    this.renderPlan = emptyEditRenderPlan()
    this.editingConfigReady = false
    if (this.dlpRegistered && canIUse("SystemCapability.Security.DlpAntiPeep")) {
      try {
        dlpAntiPeep.off('dlpAntiPeep', this.onStatusChange);
        this.dlpRegistered = false
      } catch (error) {
        console.error(`Failed to off DlpAntiPeep. Code: ${error.code}, message: ${error.message}`);
      }
    }
    if (AppManager.uiState.debug_log) {
      MemoryDiagnosticsService.checkLeaksDelayed('EditPage.afterDisappear')
    }
  }

  @Builder
  pageContent(section: EditSectionRenderPlan, index: number) {
    Column() {
      if (this.shouldMountSection(index)) {
        EditSectionView({ section: section })
      } else {
        Blank()
          .width('100%')
          .height('100%')
      }
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
    .displayCount(this.visiblePageCount())
    .cachedCount(0, false)
    .loop(false)
    .indicator(DotIndicator.dot().top(46))
    .onAnimationStart((index: number, targetIndex: number) => {
      this.updateSwipeTarget(targetIndex)
      this.enqueueNearbySectionLoads(targetIndex)
    })
    .onAnimationEnd((index: number) => {
      this.activePageIndex = index
      this.animationTargetIndex = -1
      this.enqueueNearbySectionLoads(index)
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
          subTitle: this.remoteEditing && this.remoteDeviceName.length > 0 ? this.remoteDeviceName : this.uuid!
        },
        menu: {
          value: this.remoteEditing ? [
	            HdsMenuButton($r("app.string.i18_delete"), $r("sys.symbol.trash"), async () => {
	              const configId = this.uuid!
	              try {
	                const ok = await RemoteManageService.deleteConfig(configId, this.remoteSessionId)
	                if (ok) {
	                  sendToast('远端配置已删除', $r('sys.symbol.checkmark_circle'), 0)
	                  HMRouterMgr.pop()
	                } else {
	                  sendToast('删除失败', $r('sys.symbol.exclamationmark_circle'), 1)
	                }
	              } catch (error) {
	                Logger.error(`[RemoteEditSession] remote delete failed: ${(error as Error).message}`, 'EditPage')
	                sendToast('删除失败', $r('sys.symbol.exclamationmark_circle'), 1)
	              }
	            }),
            HdsMenuButton($r("app.string.i18_rename"), $r("sys.symbol.pencil_line_1"), () => {
              EventHelper.emitterPublish("edit_open_sheet", {
                data: {
                  type: "rename"
                }
              })
            })
          ] : [
            HdsMenuButton($r("app.string.i18_favorite"),
              AppManager.data.isFavorite(this.uuid!) ? $r("sys.symbol.star_fill") : $r("sys.symbol.star"), () => {
                AppManager.data.changeFavorite(this.uuid!)
              }),
            HdsMenuButton($r("app.string.i18_share"), $r("sys.symbol.rectangle_and_arrowshape_turn_up_right_fill"),
              async () => {
                this.closeShareMenu()
                let uiContext = this.getUIContext();
                let promptAction = uiContext.getPromptAction();
                let contentNode: ComponentContent<ShareMenuParam> = new ComponentContent(uiContext, wrapBuilder(ShareMenu),
                  new ShareMenuParam(() => {
                    this.closeShareMenu()
                    this.showQr()
                  }));
                this.shareMenuContent = contentNode
                promptAction.openMenu(
                  contentNode,
                  { id: this.share_menu_id },
                  {
                    onDisappear: () => {
                      this.disposeShareMenuContent(contentNode)
                    }
                  }
                ).catch(() => {
                  this.disposeShareMenuContent(contentNode)
                })
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
          this.clearSheetState()
        }
      }
    })
  }

	  immersiveCallback = (sharableTarget: harmonyShare.SharableTarget) => {
	    if (this.remoteEditing) {
	      return
	    }
	    let config: ConfigJson | undefined = this.uuid ? AppManager.easytier.getConfig(this.uuid) : undefined
    if (config) {
      buildShareData(config, (data) => {
        sharableTarget.share(data);
      }, false, this.name, this.uuid)
    }
  }

  private editOpenSheetCallback = (data: emitter.EventData) => {
    this.sheet_type = data.data!.type as string
    this.sheet = true
  }

  private editCloseSheetCallback = () => {
    this.sheet = false
    this.refreshTitle()
  }

  private refreshTitle(): void {
    this.titleText = getStoredConfigLabel(this.uuid, this.uuid ?? '')
  }

  private resetSectionLoading(): void {
    this.sectionLoadGeneration += 1
    this.loadedSectionKeys.clear()
    this.loadingSectionKeys.clear()
	    this.sectionLoadQueue = []
	    this.sectionLoadBusy = false
	    this.sectionPreloadQueued = false
	    this.sectionLoadFailureCounts.clear()
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
	    const generation = this.sectionLoadGeneration
	    let retryDelay = -1
	    this.sectionLoadBusy = true
	    this.loadingSectionKeys.add(section.key)
	    ensureEditingFieldsAsync(this.uuid, section.topLevelFields).then(() => {
	      if (!this.active || generation !== this.sectionLoadGeneration) {
	        return
	      }
	      this.sectionLoadFailureCounts.delete(section.key)
	      this.loadedSectionKeys.add(section.key)
	      if (index === 0) {
	        this.scheduleTrailingSectionPreload()
	      }
	    }).catch(() => {
	      if (!this.active || generation !== this.sectionLoadGeneration) {
	        return
	      }
	      const failureCount = this.sectionLoadFailureCounts.get(section.key) ?? 0
	      if (failureCount < 2) {
	        this.sectionLoadFailureCounts.set(section.key, failureCount + 1)
	        retryDelay = 800
	      } else {
	        sendToast('读取配置字段失败', $r('sys.symbol.exclamationmark_circle'), 1)
	      }
	    }).finally(() => {
	      if (generation !== this.sectionLoadGeneration) {
	        return
	      }
	      this.loadingSectionKeys.delete(section.key)
	      this.sectionLoadBusy = false
	      if (this.active && retryDelay >= 0) {
	        this.enqueueSectionLoad(index, true, retryDelay)
	        return
	      }
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
      this.enqueueNearbySectionLoads(this.activePageIndex)
    }, 180)
  }

  private enqueueNearbySectionLoads(index: number): void {
    this.enqueueSectionLoad(index, true)
    this.enqueueSectionLoad(index - 1, false)
    this.enqueueSectionLoad(index + 1, false)
  }

  private visiblePageCount(): number {
    return Math.max(1, Math.floor(WindowUtil.uiType / 2))
  }

  private isPageInWindow(index: number, start: number): boolean {
    const count = this.visiblePageCount()
    return index >= start && index < start + count
  }

  private shouldMountSection(index: number): boolean {
    if (this.isPageInWindow(index, this.activePageIndex)) {
      return true
    }
    return this.animationTargetIndex >= 0 && this.isPageInWindow(index, this.animationTargetIndex)
  }

  private updateSwipeTarget(targetIndex: number): void {
    this.animationTargetIndex = this.isValidSectionIndex(targetIndex) ? targetIndex : -1
  }

  private closeShareMenu(): void {
    const content: ComponentContent<Object> | undefined = this.shareMenuContent
    if (!content) {
      return
    }
    this.shareMenuContent = undefined
    try {
      this.getUIContext().getPromptAction().closeMenu(content).catch(() => {
      }).finally(() => {
        content.dispose()
      })
    } catch (_) {
      content.dispose()
    }
  }

  private disposeShareMenuContent(content: ComponentContent<Object>): void {
    if (this.shareMenuContent !== content) {
      return
    }
    this.shareMenuContent = undefined
    try {
      content.dispose()
    } catch (_) {
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

  private async showQr(): Promise<void> {
    const editingId = this.uuid
    let config: ConfigJson | undefined = editingId ? AppManager.easytier.getConfig(editingId) : undefined
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

  private clearSheetState(): void {
    if (this.sheet_type.startsWith('add_')) {
      const addInfo = this.sheet_type.substring(4).split('|')
      clearEditValue(addInfo[0])
    } else if (this.sheet_type.startsWith('edit_')) {
      const editInfo = this.sheet_type.substring(5).split('|')
      clearEditValue(editInfo[0])
    }
    this.sheet = false
    this.sheet_type = ''
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
}
