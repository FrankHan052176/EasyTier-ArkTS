import { HMRouter, HMRouterMgr } from '@hadss/hmrouter'
import { deviceInfo, emitter } from '@kit.BasicServicesKit'
import { HdsNavigation, HdsNavigationTitleMode,
  hdsMaterial,
  TitleBarStyleOptions} from '@kit.UIDesignKit'
import { ComponentContent, FrameCallback, LengthMetrics } from '@kit.ArkUI'
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
import { perfLog, PerfSpan } from '../../services/runtime/PerfTrace'
import { RemoteManageService } from '../../services/remote/RemoteManageService'
import { sendToast } from '../../ToastUtil'
import { setEditingConfigFieldSyncSuspended } from '../../ConfigSyncUtil'

class ShareMenuParam {
  onQrClick: () => void

  constructor(onQrClick: () => void) {
    this.onQrClick = onQrClick
  }
}

class SectionMountFrameCallback extends FrameCallback {
  private readonly action: () => void
  private fired: boolean = false

  constructor(action: () => void) {
    super()
    this.action = action
  }

  onFrame(frameTimeInNano: number): void {
    this.run()
  }

  private run(): void {
    if (this.fired) {
      return
    }
    this.fired = true
    this.action()
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

/**
 * 标题栏滚动实时模糊 + 系统材质开关。
 * A/B 已验证它不是掉帧主因，恢复为开启；留成常量方便随时对比。
 */
const EDIT_TITLE_SCROLL_EFFECT = true

/**
 * 分组挂载策略开关（用于 A/B 实测）：
 * true  = 每帧挂一个分组，把构建成本摊到进场后的若干帧
 * false = 数据就绪后一次性挂载全部分组（旧行为）
 */
const STAGGER_SECTION_MOUNT = true

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
  @Local initialLoadFailed: boolean = false
  @Local titleText: string = ""
  @Local remoteEditing: boolean = false
  @Local remoteDeviceName: string = ""
  @Local remoteSessionId: string = ""
  @Local activePageIndex: number = 0
  @Local animationTargetIndex: number = -1
  @Local sectionMountRevision: number = 0
  @Local allSectionsMounted: boolean = false
  private qrPixelMap: image.PixelMap | undefined = undefined
  private qrDialogController: CustomDialogController | null = null
  private renderPlan: EditRenderPlan = emptyEditRenderPlan()
  private active: boolean = false
  private dlpRegistered: boolean = false
  private dataLoadedSectionKeys: Set<string> = new Set()
  private mountedSectionKeys: Set<string> = new Set()
  private loadingSectionKeys: Set<string> = new Set()
  private sectionLoadQueue: number[] = []
  private sectionLoadTimer: number = -1
  private sectionPreloadTimer: number = -1
  private sectionMountTimer: number = -1
  private initialSectionLoadTimer: number = -1
  private sectionPreloadQueued: boolean = false
  private sectionMountScheduled: boolean = false
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
    const appearSpan = new PerfSpan('edit.aboutToAppear')
    setEditingConfigFieldSyncSuspended(false)
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
    this.sectionMountRevision = 0
    this.resetSectionLoading()
    const prepareSpan = new PerfSpan('edit.prepareEditingConfig')
    prepareEditingConfig(this.uuid)
    prepareSpan.end()
    const planSpan = new PerfSpan('edit.buildEditRenderPlan')
    this.renderPlan = buildEditRenderPlan()
    planSpan.end(`sections=${this.renderPlan.sections.length} ${this.renderPlan.sections.map((s: EditSectionRenderPlan,
      i: number) => `${i}:${s.key}(${s.topLevelFields.length}f)`).join(',')}`)
    this.loadInitialSectionData()
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
    appearSpan.end(`uuid=${this.uuid}`)
  }

  aboutToDisappear(): void {
    setEditingConfigFieldSyncSuspended(true)
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
      // 必须和下面共用同一个分支：如果给 allSectionsMounted 单独开一个
      // if 分支，标志位翻转时 ArkUI 会认为分支变了，把已经建好的组件树
      // 销毁重建（实测每个分组会 didBuild 两次）。
      // 这里靠 || 短路：全部挂载后不再读 sectionMountRevision /
      // shouldMountSection，翻页时写那些状态就不会把 ForEach 标脏。
      if (this.allSectionsMounted ||
        (this.sectionMountRevision >= 0 && this.shouldMountSection(index) && this.isSectionLoaded(section))) {
        EditSectionView({ section: section })
      } else if (this.shouldMountSection(index)) {
        EditSectionView({ section: section, ready: false })
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
    // 固定值：运行期改 cachedCount 会让 Swiper 整体重新 measure，
    // 之前的分级提升方案实测适得其反（CreateTaskMeasure[Swiper] 单次到 43ms）。
    .cachedCount(1, false)
    .loop(false)
    .indicator(DotIndicator.dot().top(46))
    .onAnimationStart((index: number, targetIndex: number) => {
      // 全部就绪后翻页不需要任何状态写入，直接返回，别在动画途中标脏
      if (this.allSectionsMounted) {
        return
      }
      const span = new PerfSpan('edit.onAnimationStart')
      this.updateSwipeTarget(targetIndex)
      this.enqueueNearbySectionLoads(targetIndex)
      const targetSection: EditSectionRenderPlan | undefined = this.renderPlan.sections[targetIndex]
      span.end(`from=${index} to=${targetIndex} targetMounted=${targetSection !== undefined &&
        this.mountedSectionKeys.has(targetSection.key)} targetDataLoaded=${targetSection !== undefined &&
        this.dataLoadedSectionKeys.has(targetSection.key)}`)
    })
    .onAnimationEnd((index: number) => {
      this.activePageIndex = index
      if (this.allSectionsMounted) {
        return
      }
      const span = new PerfSpan('edit.onAnimationEnd')
      this.animationTargetIndex = -1
      this.sectionMountRevision++
      this.enqueueNearbySectionLoads(index)
      this.scheduleSectionMount()
      span.end(`index=${index} mounted=${this.mountedSectionKeys.size} loaded=${this.dataLoadedSectionKeys.size}`)
    })
  }

  @Builder
  loadingContent() {
    Column({ space: 12 }) {
      if (this.initialLoadFailed) {
        SymbolGlyph($r('sys.symbol.exclamationmark_circle'))
          .fontSize(32)
          .fontColor([$r('sys.color.font_secondary')])
        Text('配置载入失败')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('sys.color.font_primary'))
        Text('请检查配置文件或远端连接后重试')
          .fontSize(14)
          .fontColor($r('sys.color.font_secondary'))
          .textAlign(TextAlign.Center)
        Button('重新载入')
          .type(ButtonType.Capsule)
          .onClick(() => {
            this.retryInitialLoading()
          })
      } else {
        LoadingProgress()
          .width(36)
          .height(36)
        Text('正在加载配置')
          .fontSize(14)
          .fontColor($r('sys.color.font_secondary'))
      }
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  navTitleStyle(): TitleBarStyleOptions {
    if (deviceInfo.distributionOSApiVersion >= 60100 && hdsMaterial.getSystemMaterialTypes().length > 0) {
      if (!EDIT_TITLE_SCROLL_EFFECT) {
        // A/B 排查：关掉标题栏实时模糊后的对照样式
        return {
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
          }
        }
      }
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
        scrollEffectOpts: EDIT_TITLE_SCROLL_EFFECT ? {
          enableScrollEffect: true,
          scrollEffectType: deviceInfo.sdkApiVersion >= 23 ? 3 : 2,
          blurEffectiveStartOffset: LengthMetrics.vp(0),
          blurEffectiveEndOffset: LengthMetrics.vp(20),
        } : undefined,
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
          value: this.remoteEditing ? [] : [
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
            HdsMenuButton('复制配置', $r("sys.symbol.doc"), () => {
              const copiedId = AppManager.data.copyConfig(this.uuid!)
              sendToast(copiedId ? '已复制配置' : '复制配置失败',
                copiedId ? $r('sys.symbol.checkmark_circle') : $r('sys.symbol.exclamationmark_circle'),
                copiedId ? 0 : 1)
            }),
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
    this.dataLoadedSectionKeys.clear()
    this.mountedSectionKeys.clear()
    this.loadingSectionKeys.clear()
	    this.sectionLoadQueue = []
	    this.sectionPreloadQueued = false
	    this.sectionMountScheduled = false
	    this.sectionLoadFailureCounts.clear()
    if (this.sectionLoadTimer >= 0) {
      clearTimeout(this.sectionLoadTimer)
      this.sectionLoadTimer = -1
    }
    if (this.sectionPreloadTimer >= 0) {
      clearTimeout(this.sectionPreloadTimer)
      this.sectionPreloadTimer = -1
    }
    if (this.sectionMountTimer >= 0) {
      clearTimeout(this.sectionMountTimer)
      this.sectionMountTimer = -1
    }
    if (this.initialSectionLoadTimer >= 0) {
      clearTimeout(this.initialSectionLoadTimer)
      this.initialSectionLoadTimer = -1
    }
    this.allSectionsMounted = false
    this.initialLoadFailed = false
  }

  private isValidSectionIndex(index: number): boolean {
    return index >= 0 && index < this.renderPlan.sections.length
  }

  private isSectionQueued(index: number): boolean {
    return this.sectionLoadQueue.indexOf(index) >= 0
  }

  private isSectionLoaded(section: EditSectionRenderPlan): boolean {
    return this.mountedSectionKeys.has(section.key)
  }

  private enqueueSectionLoad(index: number, highPriority: boolean = false, delayMs: number = 0): void {
    if (!this.isValidSectionIndex(index)) {
      return
    }
    const section = this.renderPlan.sections[index]
    if (this.dataLoadedSectionKeys.has(section.key) || this.loadingSectionKeys.has(section.key) || this.isSectionQueued(index)) {
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
    if (!this.active || this.sectionLoadQueue.length === 0) {
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
      if (!this.dataLoadedSectionKeys.has(section.key) && !this.loadingSectionKeys.has(section.key)) {
        return index
      }
    }
    return -1
  }

  private drainSectionLoadQueue(): void {
    if (!this.active) {
      return
    }
    let started = 0
    const maxStarted = Math.max(2, this.visiblePageCount())
    while (started < maxStarted) {
      const index = this.takeNextSectionIndex()
      if (index < 0) {
        return
      }
      this.loadSectionData(index)
      started++
    }
    if (this.sectionLoadQueue.length > 0) {
      this.scheduleSectionLoadDrain(16)
    }
  }

  private allSectionFields(): string[] {
    const fields: string[] = []
    this.renderPlan.sections.forEach((section) => {
      section.topLevelFields.forEach((field) => {
        if (field.length > 0 && fields.indexOf(field) < 0) {
          fields.push(field)
        }
      })
    })
    return fields
  }

  private areAllSectionsDataLoaded(): boolean {
    return this.renderPlan.sections.every((section) => this.dataLoadedSectionKeys.has(section.key))
  }

  /**
   * 数据全部就绪，但**不**一次性挂载所有分组。
   * 进场那一帧如果把 4 个分组的组件树全建出来，实测单帧 136.9ms
   * （同一帧要 measure 两个 List，内嵌十几次组件构建）。
   * 这里只标记数据可用，挂载交给 scheduleSectionMount 每帧挂一个，
   * 把构建成本摊到进场后的若干空闲帧里。
   */
  private markAllSectionsReady(): void {
    this.renderPlan.sections.forEach((section) => {
      this.dataLoadedSectionKeys.add(section.key)
      this.loadingSectionKeys.delete(section.key)
      if (!STAGGER_SECTION_MOUNT) {
        this.mountedSectionKeys.add(section.key)
      }
    })
    this.sectionLoadQueue = []
    this.sectionMountRevision++
    if (STAGGER_SECTION_MOUNT) {
      this.scheduleSectionMount()
    } else {
      this.allSectionsMounted = true
    }
  }

  /** 全部分组都挂载完之后，才切到短路分支（翻页不再写状态） */
  private syncAllMountedFlag(): void {
    if (this.allSectionsMounted || this.renderPlan.sections.length === 0) {
      return
    }
    const done = this.renderPlan.sections.every((section) => this.mountedSectionKeys.has(section.key))
    if (done) {
      this.allSectionsMounted = true
      perfLog(`edit.allSectionsMounted sections=${this.renderPlan.sections.length}`)
    }
  }

  private loadInitialSectionData(delayMs: number = 0): void {
    if (!this.active || this.renderPlan.sections.length === 0) {
      return
    }
    if (delayMs > 0) {
      if (this.initialSectionLoadTimer >= 0) {
        clearTimeout(this.initialSectionLoadTimer)
      }
      this.initialSectionLoadTimer = setTimeout(() => {
        this.initialSectionLoadTimer = -1
        this.loadInitialSectionData()
      }, delayMs)
      return
    }
    if (this.areAllSectionsDataLoaded()) {
      this.markAllSectionsReady()
      this.editingConfigReady = true
      this.initialLoadFailed = false
      return
    }
    const generation = this.sectionLoadGeneration
    const fields = this.allSectionFields()
    this.renderPlan.sections.forEach((section) => {
      if (!this.dataLoadedSectionKeys.has(section.key)) {
        this.loadingSectionKeys.add(section.key)
      }
    })
    const initialSpan = new PerfSpan('edit.loadInitialSectionData')
    ensureEditingFieldsAsync(this.uuid, fields).then(() => {
      initialSpan.end(`fields=${fields.length}`)
      if (!this.active || generation !== this.sectionLoadGeneration) {
        return
      }
      this.sectionLoadFailureCounts.clear()
      this.markAllSectionsReady()
      this.editingConfigReady = true
      this.initialLoadFailed = false
    }).catch(() => {
      if (!this.active || generation !== this.sectionLoadGeneration) {
        return
      }
      const failureCount = this.sectionLoadFailureCounts.get('__initial__') ?? 0
      if (failureCount < 2) {
        this.sectionLoadFailureCounts.set('__initial__', failureCount + 1)
        this.loadInitialSectionData(300)
      } else {
        this.editingConfigReady = false
        this.initialLoadFailed = true
        sendToast('读取配置字段失败', $r('sys.symbol.exclamationmark_circle'), 1)
      }
    }).finally(() => {
      if (generation !== this.sectionLoadGeneration) {
        return
      }
      this.renderPlan.sections.forEach((section) => {
        this.loadingSectionKeys.delete(section.key)
      })
    })
  }

  private loadSectionData(index: number): void {
    const section = this.renderPlan.sections[index]
    const generation = this.sectionLoadGeneration
    let retryDelay = -1
    this.loadingSectionKeys.add(section.key)
    const loadSpan = new PerfSpan('edit.loadSectionData')
    ensureEditingFieldsAsync(this.uuid, section.topLevelFields).then(() => {
      loadSpan.end(`index=${index} key=${section.key} fields=${section.topLevelFields.length}`)
      if (!this.active || generation !== this.sectionLoadGeneration) {
        return
      }
      this.sectionLoadFailureCounts.delete(section.key)
      this.dataLoadedSectionKeys.add(section.key)
      if (index === 0) {
        this.scheduleTrailingSectionPreload()
      }
      this.scheduleSectionMount()
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
      if (this.active && retryDelay >= 0) {
        this.enqueueSectionLoad(index, true, retryDelay)
        return
      }
      if (this.active && this.sectionLoadQueue.length > 0) {
        this.scheduleSectionLoadDrain(16)
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
      this.enqueueVisibleSectionLoads(this.activePageIndex, 32)
    }, 180)
  }

  private scheduleSectionMount(): void {
    if (!this.active || this.sectionMountScheduled) {
      return
    }
    if (!this.canMountVisibleWindow() && this.nextPreloadMountIndex() < 0) {
      return
    }
    this.sectionMountScheduled = true
    const generation = this.sectionLoadGeneration
    const callback = () => {
      if (!this.active || generation !== this.sectionLoadGeneration) {
        return
      }
      this.sectionMountScheduled = false
      this.mountNextReadySection()
    }
    try {
      this.getUIContext().postFrameCallback(new SectionMountFrameCallback(callback))
    } catch (_) {
      this.sectionMountTimer = setTimeout(() => {
        this.sectionMountTimer = -1
        callback()
      }, 16)
    }
  }

  private mountNextReadySection(): void {
    if (!this.active) {
      return
    }
    if (this.animationTargetIndex >= 0) {
      return
    }
    const visibleStart = this.visibleWindowStart(this.activePageIndex)
    const visibleCount = this.visiblePageCount()
    let mounted = false
    if (this.canMountVisibleWindow()) {
      for (let offset = 0; offset < visibleCount; offset++) {
        const index = visibleStart + offset
        if (this.canMountSection(index)) {
          const section = this.renderPlan.sections[index]
          this.mountedSectionKeys.add(section.key)
          perfLog(`edit.mountVisible index=${index} key=${section.key}`)
          mounted = true
        }
      }
    } else {
      // 当前窗口已就绪，利用空闲帧预挂载相邻分组（每帧一个），
      // 这样首次前滑/后滑都能复用现成组件树，不在动画中途构建。
      const preloadIndex = this.nextPreloadMountIndex()
      if (preloadIndex >= 0) {
        this.mountedSectionKeys.add(this.renderPlan.sections[preloadIndex].key)
        perfLog(`edit.preloadMount index=${preloadIndex} key=${this.renderPlan.sections[preloadIndex].key}`)
        mounted = true
      }
    }
    if (mounted) {
      this.sectionMountRevision++
      this.syncAllMountedFlag()
      this.scheduleSectionMount()
    }
  }

  /**
   * 下一个待挂载的分组：先相邻页，再其余任意未挂载分组。
   * 每帧只返回一个，配合 postFrameCallback 把构建摊到多帧。
   */
  private nextPreloadMountIndex(): number {
    const visibleStart = this.visibleWindowStart(this.activePageIndex)
    const visibleCount = this.visiblePageCount()
    const candidates: number[] = [visibleStart + visibleCount, visibleStart - 1]
    for (const index of candidates) {
      if (this.canMountSection(index)) {
        return index
      }
    }
    for (let index = 0; index < this.renderPlan.sections.length; index++) {
      if (this.canMountSection(index)) {
        return index
      }
    }
    return -1
  }

  private canMountVisibleWindow(): boolean {
    const visibleStart = this.visibleWindowStart(this.activePageIndex)
    const visibleCount = this.visiblePageCount()
    let hasUnmountedVisible = false
    for (let offset = 0; offset < visibleCount; offset++) {
      const index = visibleStart + offset
      if (!this.isValidSectionIndex(index)) {
        continue
      }
      const section = this.renderPlan.sections[index]
      if (this.mountedSectionKeys.has(section.key)) {
        continue
      }
      hasUnmountedVisible = true
      if (!this.dataLoadedSectionKeys.has(section.key)) {
        return false
      }
    }
    return hasUnmountedVisible
  }

  private canMountSection(index: number): boolean {
    if (!this.isValidSectionIndex(index)) {
      return false
    }
    const section = this.renderPlan.sections[index]
    return this.dataLoadedSectionKeys.has(section.key) && !this.mountedSectionKeys.has(section.key)
  }

  private enqueueNearbySectionLoads(index: number, delayMs: number = 0): void {
    this.enqueueVisibleSectionLoads(index, delayMs)
  }

  private enqueueVisibleSectionLoads(index: number, delayMs: number = 0): void {
    const start = this.visibleWindowStart(index)
    const count = this.visiblePageCount()
    this.enqueueSectionLoad(index, true, delayMs)
    for (let offset = 0; offset < count; offset++) {
      const sectionIndex = start + offset
      if (sectionIndex !== index) {
        this.enqueueSectionLoad(sectionIndex, false, delayMs)
      }
    }
    this.enqueueSectionLoad(start - 1, false, delayMs)
    this.enqueueSectionLoad(start + count, false, delayMs)
  }

  private visiblePageCount(): number {
    return Math.max(1, Math.floor(WindowUtil.uiType / 2))
  }

  private visibleWindowStart(start: number): number {
    const count = this.visiblePageCount()
    const maxStart = Math.max(0, this.renderPlan.sections.length - count)
    return Math.min(Math.max(0, start), maxStart)
  }

  private retryInitialLoading(): void {
    if (!this.active) {
      return
    }
    this.editingConfigReady = false
    this.resetSectionLoading()
    this.loadInitialSectionData()
  }

  private isPageInWindow(index: number, start: number): boolean {
    const count = this.visiblePageCount()
    const windowStart = this.visibleWindowStart(start)
    return index >= windowStart && index < windowStart + count
  }

  private shouldMountSection(index: number): boolean {
    if (this.isPageInWindow(index, this.activePageIndex)) {
      return true
    }
    if (this.animationTargetIndex >= 0 && this.isPageInWindow(index, this.animationTargetIndex)) {
      return true
    }
    // 已构建过的分组保持挂载：滑走时不再拆掉组件树，回滑时直接复用。
    // 否则 onAnimationStart 才把目标页放回窗口，整页要在滑动动画进行中
    // 重新构建 + 布局，必然掉帧（“第二页划回第一页卡顿”的根因）。
    const section: EditSectionRenderPlan | undefined = this.renderPlan.sections[index]
    return section !== undefined && this.mountedSectionKeys.has(section.key)
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
