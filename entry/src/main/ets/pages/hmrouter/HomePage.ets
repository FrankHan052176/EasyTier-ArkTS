import { HMRouter, HMRouterMgr } from '@hadss/hmrouter';
import { deviceInfo, emitter } from '@kit.BasicServicesKit';
import { common } from '@kit.AbilityKit';
import { HdsNavigation, HdsNavigationTitleMode, TitleBarStyleOptions } from '@hms.hds.hdsBaseComponent';
import { LengthMetrics } from '@kit.ArkUI';
import { AppManager } from '../../AppManager';
import { EventHelper } from '../../util/EventHelper';
import { HomeSheetContentBuilder } from '../../components/sheet/HomeSheet';
import { setConfigName } from '../../components/sheet/NewConfig';
import { hdsMaterial } from '@kit.UIDesignKit';
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
import {
  REMOTE_MANAGE_CONNECTION_EVENT,
  REMOTE_MANAGE_SUMMARY_DIRTY_EVENT,
  RemoteManageService
} from '../../services/remote/RemoteManageService';
import { RemoteSummary } from '../../services/remote/RemoteManageTypes';
import { HdsMenuButton } from '../Components';
import { NatTypeValue, RuntimeInstanceState } from '../../types/runtime/RuntimeTypes';
import { CompSizeWithPos, DesktopLayout, LayoutUtil } from '../../components/layout/desktop/DesktopGridLayout';

const HOME_CARD_TYPES: string[] = ['Instances', 'Logs', 'Favorite', 'SharedPeers', 'QQ']
const HOME_DEFAULT_CARD_SEQUENCE: CompSizeWithPos[] = [
  { type: 'Instances', x: 0, y: 0, width: 2, height: 1 },
  { type: 'Logs', x: 2, y: 0, width: 2, height: 1 },
  { type: 'Favorite', x: 4, y: 0, width: 2, height: 1 },
  { type: 'SharedPeers', x: 0, y: 1, width: 2, height: 1 },
  { type: 'QQ', x: 2, y: 1, width: 2, height: 1 }
]

function natTypeText(value: NatTypeValue | undefined): string {
  if (value === undefined || value === NatTypeValue.Unknown) {
    return 'Unknown'
  }
  switch (value) {
    case NatTypeValue.OpenInternet:
      return 'OpenInternet'
    case NatTypeValue.NoPAT:
      return 'NoPAT'
    case NatTypeValue.FullCone:
      return 'FullCone'
    case NatTypeValue.Restricted:
      return 'Restricted'
    case NatTypeValue.PortRestricted:
      return 'PortRestricted'
    case NatTypeValue.Symmetric:
      return 'Symmetric'
    case NatTypeValue.SymUdpFirewall:
      return 'SymUdpFirewall'
    case NatTypeValue.SymmetricEasyInc:
      return 'SymmetricEasyInc'
    case NatTypeValue.SymmetricEasyDec:
      return 'SymmetricEasyDec'
    default:
      return `${value}`
  }
}

@Builder
function buildHomeComp(type: string) {
  if (type === 'Instances') {
    Instances()
  } else if (type === 'Logs') {
    HomeLogsCard()
  } else if (type === 'Favorite') {
    Favorite()
  } else if (type === 'SharedPeers') {
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
  controlScroller: Scroller = new Scroller();
  localActionScroller: Scroller = new Scroller();
  crossActionScroller: Scroller = new Scroller();
  private homeSwiperController: SwiperController = new SwiperController()
  @Local homePageIndex: number = 0
  @Local sheet: boolean = false
  @Local sheet_type: string = ""
  @Local tips: string | undefined = ""
  @Local actionText: string | undefined = ""
  @Local remoteRevision: number = 0
  @Local qqGroups: string[] = []
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
  private remoteManageChangedCallback = (_data: emitter.EventData) => {
    this.remoteRevision++
  }
  private qqGroupsChangedCallback = (data: emitter.EventData) => {
    this.qqGroups = data.data?.groups as string[] ?? []
  }

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
    EventHelper.emitterListener(REMOTE_MANAGE_CONNECTION_EVENT, this.remoteManageChangedCallback)
    EventHelper.emitterListener(REMOTE_MANAGE_SUMMARY_DIRTY_EVENT, this.remoteManageChangedCallback)
    EventHelper.emitterListener("update_qqgroups", this.qqGroupsChangedCallback)
    this.qqGroups = AppManager.web.qqgroups
    AppManager.web.updateQQGroups()
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
    EventHelper.emitterOff(REMOTE_MANAGE_CONNECTION_EVENT, this.remoteManageChangedCallback)
    EventHelper.emitterOff(REMOTE_MANAGE_SUMMARY_DIRTY_EVENT, this.remoteManageChangedCallback)
    EventHelper.emitterOff("update_qqgroups", this.qqGroupsChangedCallback)
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

  startAndStop(): void {
    if (AppManager.easytier.runningNetworks.size > 0) {
      AppManager.easytier.stop()
    } else {
      AppManager.easytier.start()
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

  private favoriteConfigName(): string {
    const favorite = AppManager.uiState.favorite
    if (!favorite) {
      return '未收藏'
    }
    return AppManager.easytier.getConfigName(favorite) ?? 'Unknown'
  }

  private selectedUuid(): string | undefined {
    const selected = AppManager.uiState.selected
    return selected && AppManager.data.configIds.includes(selected) ? selected : undefined
  }

  private selectInstance(uuid: string): void {
    AppManager.uiState.selected = uuid
  }

  private selectedRunningInstance(): RuntimeInstanceState | undefined {
    const uuid = this.selectedUuid()
    return uuid ? AppManager.easytier.getRunningInstance(uuid) : undefined
  }

  private selectedVirtualIp(): string {
    const running = this.selectedRunningInstance()
    return running?.myNodeInfo?.virtualIpv4Cidr ?? running?.myNodeInfo?.virtualIpv4 ?? '等待分配'
  }

  private selectedNatText(): string {
    const running = this.selectedRunningInstance()
    return `UDP ${natTypeText(running?.myNodeInfo?.udpNatType)} · TCP ${natTypeText(running?.myNodeInfo?.tcpNatType)}`
  }

  private selectedPeerCountText(): string {
    return (this.selectedRunningInstance()?.peers.length ?? 0).toString()
  }

  private selectedRouteCountText(): string {
    return (this.selectedRunningInstance()?.routes.length ?? 0).toString()
  }

  private visiblePageCount(): number {
    return Math.min(3, Math.max(1, Math.floor(WindowUtil.uiType / 2)))
  }

  private isExpandedHomeLayout(): boolean {
    return this.visiblePageCount() > 1
  }

  private maxHomePageIndex(): number {
    return Math.max(0, 3 - this.visiblePageCount())
  }

  private effectiveHomePageIndex(): number {
    return Math.min(this.homePageIndex, this.maxHomePageIndex())
  }

  private isHomePageVisible(index: number): boolean {
    const start = this.effectiveHomePageIndex()
    return index >= start && index < start + this.visiblePageCount()
  }

  private switchHomePage(index: number): void {
    const target = Math.max(0, Math.min(index, this.maxHomePageIndex()))
    try {
      this.homeSwiperController.changeIndex(target, true)
    } catch (_) {
    }
    this.homePageIndex = target
  }

  private pageTopInset(): number {
    return this.visiblePageCount() >= 3 ? 72 : 96
  }

  private pageHorizontalPadding(): number {
    return this.isExpandedHomeLayout() ? 12 : 16
  }

  private pageBottomInset(): number {
    return 24
  }

  private startSelectedInstance(): void {
    const uuid = this.selectedUuid()
    if (!uuid) {
      this.openNewSheet()
      return
    }
    if (!AppManager.easytier.start(uuid)) {
      sendToast('实例启动失败', $r('sys.symbol.exclamationmark_circle'), 1)
    }
  }

  private versionText(): string {
    return "v" + AppManager.easytier.version().split("-")[0]
  }

  private runningSummaryText(): string {
    const runningCount = AppManager.easytier.runningNetworks.size
    return runningCount > 0 ? `${runningCount} 个实例运行中` : '服务未运行'
  }

  private selectedInstanceName(): string {
    const uuid = this.selectedUuid()
    return uuid ? AppManager.easytier.getConfigLabel(uuid, uuid) : '未选择实例'
  }

  private selectedInstanceStateText(): string {
    if (!this.selectedUuid()) {
      return '未选择'
    }
    return this.selectedRunningInstance() ? '运行中' : '未运行'
  }

  private startStopIcon(): Resource {
    return this.selectedRunningInstance() ? $r('sys.symbol.pause_fill') : $r('sys.symbol.play_fill')
  }

  private startStopText(): string {
    if (!this.selectedUuid()) {
      return '新建'
    }
    return this.selectedRunningInstance() ? '停止' : '启动'
  }

  private editSelected(): void {
    const uuid = this.selectedUuid()
    if (!uuid) {
      this.openNewSheet()
      return
    }
    HMRouterMgr.push({ pageUrl: 'EditPage', param: { uuid: uuid, unsafe: true } })
  }

  private latestLogText(): string {
    const count = AppManager.easytier.appLogs.totalCount()
    if (count <= 0) {
      return '暂无日志'
    }
    const raw = AppManager.easytier.appLogs.getData(count - 1)
    const level = Number.parseInt(raw.charAt(0))
    return Number.isNaN(level) ? raw : raw.substring(1)
  }

  private remoteSummary(): RemoteSummary | undefined {
    if (this.remoteRevision < 0) {
      return undefined
    }
    return RemoteManageService.cachedSummary
  }

  private remoteDeviceText(): string {
    const summary = this.remoteSummary()
    const name = summary?.deviceName ?? RemoteManageService.currentDeviceName
    if (RemoteManageService.connected && name.length > 0) {
      return name
    }
    return '管理组网设备上的 EasyTier'
  }

  private remoteDetailText(): string {
    const summary = this.remoteSummary()
    const runningCount = summary?.runtime.runningCount ?? 0
    const configCount = summary?.configs.length ?? 0
    return RemoteManageService.connected ? `${runningCount} 运行 · ${configCount} 配置` : '待连接'
  }

  private qqGroupCount(): number {
    return this.qqGroups.length + 1
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

  private openLogsSheet(): void {
    this.sheet_type = "logs"
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
    return type === 'RemoteControl' ? 'SharedPeers' : type
  }

  private homeCardSequence(): CompSizeWithPos[] {
    if (AppManager.uiState.raw_comp_sequence.includes('Control_')) {
      return this.homeDefaultCardSequence()
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

    HOME_DEFAULT_CARD_SEQUENCE.forEach((item: CompSizeWithPos) => {
      if (!seen.includes(item.type)) {
        parsed.push({
          type: item.type,
          x: item.x,
          y: item.y,
          width: item.width,
          height: item.height
        } as CompSizeWithPos)
      }
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

  private toggleFavorite(): void {
    const favorite = AppManager.uiState.favorite
    if (!favorite) {
      sendToast('先在实例中设置收藏', $r('sys.symbol.exclamationmark_circle'), 1)
      return
    }
    if (AppManager.easytier.isFavoritesRunning()) {
      AppManager.easytier.stop()
      return
    }
    if (AppManager.easytier.runningNetworks.size > 0) {
      AppManager.easytier.stop()
    }
    if (!AppManager.easytier.start(favorite)) {
      sendToast('收藏的实例不存在', $r('sys.symbol.exclamationmark_circle'), 1)
    }
  }

  private openQQGroup(): void {
    const qqgroup = this.qqGroups.length > 0 ? this.qqGroups[0] : '630809530'
    const context = AppManager.content.context as common.UIAbilityContext
    context.startAbility({
      uri: `mqqapi://card/show_pslcard?src_type=internal&version=1&uin=${qqgroup}&card_type=group&source=qrcode`
    }).catch(() => {
      sendToast('无法打开 QQ 群', $r('sys.symbol.exclamationmark_circle'), 1)
    })
  }

  private runningInstance(uuid: string): RuntimeInstanceState | undefined {
    return AppManager.easytier.getRunningInstance(uuid)
  }

  private isInstanceRunning(uuid: string): boolean {
    return this.runningInstance(uuid) !== undefined
  }

  private instanceStatusText(uuid: string): string {
    return this.isInstanceRunning(uuid) ? '运行中' : '已停止'
  }

  private instanceDetailText(uuid: string): string {
    const running = this.runningInstance(uuid)
    if (running) {
      const address = running.myNodeInfo?.virtualIpv4Cidr ?? running.myNodeInfo?.virtualIpv4 ?? '等待地址'
      return `${address} · ${running.peers.length} 节点`
    }
    return uuid
  }

  private toggleInstance(uuid: string): void {
    if (this.isInstanceRunning(uuid)) {
      if (!AppManager.easytier.stopConfig(uuid)) {
        sendToast('实例停止失败', $r('sys.symbol.exclamationmark_circle'), 1)
      }
      return
    }
    if (!AppManager.easytier.start(uuid)) {
      sendToast('实例启动失败', $r('sys.symbol.exclamationmark_circle'), 1)
    }
  }

  private toggleSelectedInstance(): void {
    const uuid = this.selectedUuid()
    if (!uuid) {
      this.openNewSheet()
      return
    }
    this.toggleInstance(uuid)
  }

  private selectedDetailText(): string {
    const running = this.selectedRunningInstance()
    if (running) {
      return `${this.selectedVirtualIp()} · ${running.peers.length} 节点 · ${running.routes.length} 路由`
    }
    if (this.selectedUuid()) {
      return `${AppManager.data.configIds.length} 配置 · ${AppManager.easytier.runningNetworks.size} 运行`
    }
    return '在实例页选择配置'
  }

  private selectedActionColor(): ResourceColor {
    return this.selectedRunningInstance() ? $r('sys.color.warning') : $r('sys.color.interactive_active')
  }

  @Builder
  StatusPill(text: string, active: boolean) {
    Text(text)
      .fontSize(11)
      .fontWeight(FontWeight.Medium)
      .fontColor(active ? $r('sys.color.brand_font') : $r('sys.color.font_secondary'))
      .padding({ left: 8, right: 8, top: 4, bottom: 4 })
      .borderRadius(10)
      .backgroundColor(active ? $r('sys.color.brand') : $r('sys.color.comp_background_secondary'))
      .maxLines(1)
  }

  @Builder
  PrimaryButton(icon: Resource, text: string, color: ResourceColor, action: () => void) {
    Row({ space: 6 }) {
      SymbolGlyph(icon)
        .fontSize(15)
        .fontColor(['#FFFFFFFF'])
      Text(text)
        .fontSize(13)
        .fontWeight(FontWeight.Bold)
        .fontColor('#FFFFFFFF')
        .maxLines(1)
    }
    .height(36)
    .padding({ left: 13, right: 13 })
    .borderRadius(8)
    .backgroundColor(color)
    .onClick(action)
  }

  @Builder
  IconAction(icon: Resource, active: boolean, action: () => void) {
    Row() {
      SymbolGlyph(icon)
        .fontSize(18)
        .fontColor([active ? $r('sys.color.brand_font') : $r('sys.color.font_secondary')])
    }
    .width(34)
    .height(34)
    .justifyContent(FlexAlign.Center)
    .borderRadius(8)
    .backgroundColor(active ? $r('sys.color.brand') : $r('sys.color.comp_background_secondary'))
    .onClick(action)
  }

  @Builder
  SectionTitle(title: string, trailing: string = '') {
    Row() {
      Text(title)
        .fontSize(15)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('sys.color.font_primary'))
        .maxLines(1)
      Blank()
      if (trailing.length > 0) {
        Text(trailing)
          .fontSize(11)
          .fontColor($r('sys.color.font_secondary'))
          .maxLines(1)
      }
    }
    .width('100%')
    .height(24)
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  MetricCell(label: string, value: string, accent: boolean = false) {
    Column({ space: 2 }) {
      Text(label)
        .fontSize(10)
        .fontColor($r('sys.color.font_secondary'))
        .maxLines(1)
      Text(value)
        .fontSize(15)
        .fontWeight(FontWeight.Bold)
        .fontColor(accent ? $r('sys.color.interactive_active') : $r('sys.color.font_primary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .height(42)
    .layoutWeight(1)
    .padding({ left: 6, right: 6 })
    .alignItems(HorizontalAlign.Start)
    .justifyContent(FlexAlign.Center)
    .backgroundColor(Color.Transparent)
  }

  @Builder
  InfoLine(label: string, value: string) {
    Row() {
      Text(label)
        .fontSize(12)
        .fontColor($r('sys.color.font_secondary'))
        .maxLines(1)
      Blank()
      Text(value)
        .fontSize(12)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('sys.color.font_primary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .height(30)
    .width('100%')
  }

  @Builder
  CommandRow(icon: Resource, title: string, detail: string, accent: boolean, action: () => void) {
    Row({ space: 9 }) {
      SymbolGlyph(icon)
        .fontSize(18)
        .fontColor([accent ? $r('sys.color.interactive_active') : $r('sys.color.font_primary')])
      Column({ space: 1 }) {
        Text(title)
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('sys.color.font_primary'))
          .maxLines(1)
        Text(detail)
          .fontSize(10)
          .fontColor($r('sys.color.font_secondary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(14)
        .fontColor([$r('sys.color.font_tertiary')])
    }
    .height(48)
    .width('100%')
    .padding({ left: 10, right: 8 })
    .borderRadius(8)
    .backgroundColor($r('sys.color.comp_background_primary'))
    .onClick(action)
  }

  @Builder
  GroupedCommandRow(icon: Resource, title: string, detail: string, accent: boolean, showDivider: boolean,
    action: () => void) {
    Column() {
      Row({ space: 10 }) {
        SymbolGlyph(icon)
          .fontSize(18)
          .fontColor([accent ? $r('sys.color.interactive_active') : $r('sys.color.font_primary')])
        Column({ space: 1 }) {
          Text(title)
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('sys.color.font_primary'))
            .maxLines(1)
          Text(detail)
            .fontSize(10)
            .fontColor($r('sys.color.font_secondary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(14)
          .fontColor([$r('sys.color.font_tertiary')])
      }
      .height(52)
      .width('100%')
      .padding({ left: 12, right: 10 })
      .onClick(action)

      if (showDivider) {
        Divider()
          .color($r('sys.color.comp_divider'))
          .margin({ left: 44, right: 10 })
      }
    }
    .width('100%')
  }

  @Builder
  PrimaryControl() {
    Column({ space: 10 }) {
      Row({ space: 10 }) {
        Column()
          .width(4)
          .height(44)
          .borderRadius(2)
          .backgroundColor(this.selectedRunningInstance() ? $r('sys.color.interactive_active') :
          $r('sys.color.font_tertiary'))
        Column({ space: 3 }) {
          Text(this.selectedInstanceName())
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('sys.color.font_primary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(this.selectedDetailText())
            .fontSize(11)
            .fontColor($r('sys.color.font_secondary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        if (this.selectedUuid()) {
          this.PrimaryButton(this.startStopIcon(), this.startStopText(), this.selectedActionColor(), (): void => {
            this.toggleSelectedInstance()
          })
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Row({ space: 6 }) {
        this.StatusPill(this.selectedInstanceStateText(), this.selectedRunningInstance() !== undefined)
        this.StatusPill(`${AppManager.data.configIds.length} 配置`, false)
        this.StatusPill(`${AppManager.easytier.runningNetworks.size} 运行`, AppManager.easytier.runningNetworks.size > 0)
      }
      .width('100%')
    }
    .width('100%')
    .padding(12)
    .borderRadius(8)
    .backgroundColor($r('sys.color.comp_background_primary'))
  }

  @Builder
  RuntimeSummary() {
    Column({ space: 8 }) {
      if (this.selectedRunningInstance()) {
        Row({ space: 8 }) {
          this.MetricCell('虚拟地址', this.selectedVirtualIp(), true)
          this.MetricCell('节点', this.selectedPeerCountText(), false)
        }
        .width('100%')
        Row({ space: 8 }) {
          this.MetricCell('路由', this.selectedRouteCountText(), false)
          this.MetricCell('NAT', this.selectedNatText(), false)
        }
        .width('100%')
      } else {
        Row({ space: 8 }) {
          this.MetricCell('已配置', AppManager.data.configIds.length.toString(), true)
          this.MetricCell('运行中', AppManager.easytier.runningNetworks.size.toString(), false)
        }
        .width('100%')
        Row({ space: 8 }) {
          this.MetricCell('收藏', this.favoriteConfigName(), false)
          this.MetricCell('日志', `${AppManager.easytier.appLogs.totalCount()} 条`, false)
        }
        .width('100%')
      }

      Divider()
        .color($r('sys.color.comp_divider'))
        .margin({ left: 4, right: 4 })

      this.InfoLine('最近日志', this.latestLogText())
      this.InfoLine('运行模式', AppManager.uiState.ext_mode ? 'Extension' : 'Background')
    }
    .width('100%')
    .padding({ left: 10, right: 10, top: 10, bottom: 8 })
    .borderRadius(8)
    .backgroundColor($r('sys.color.comp_background_primary'))
  }

  @Builder
  ControlActions() {
    Column() {
      this.GroupedCommandRow($r('sys.symbol.thumbnails'), '状态详情', this.runningSummaryText(), true, false, (): void => {
        this.status()
      })
    }
    .width('100%')
    .borderRadius(8)
    .backgroundColor($r('sys.color.comp_background_primary'))
  }

  @Builder
  ControlPanel() {
    Column({ space: 8 }) {
      this.SectionTitle('控制', this.runningSummaryText())
      this.PrimaryControl()
      this.RuntimeSummary()
      if (AppManager.easytier.runningNetworks.size > 0) {
        this.ControlActions()
      }
    }
    .width('100%')
  }

  @Builder
  InstanceRow(uuid: string) {
    Row({ space: 10 }) {
      Column()
        .width(3)
        .height(28)
        .borderRadius(2)
        .backgroundColor(uuid === this.selectedUuid() ? $r('sys.color.interactive_active') : Color.Transparent)
      SymbolGlyph(this.isInstanceRunning(uuid) ? $r('sys.symbol.play_circle') : $r('sys.symbol.key_shield'))
        .fontSize(17)
        .fontColor([this.isInstanceRunning(uuid) ? $r('sys.color.interactive_active') : $r('sys.color.font_secondary')])
      Column({ space: 2 }) {
        Text(AppManager.easytier.getConfigLabel(uuid, uuid))
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('sys.color.font_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(this.instanceDetailText(uuid))
          .fontSize(10)
          .fontColor($r('sys.color.font_secondary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      this.StatusPill(this.instanceStatusText(uuid), this.isInstanceRunning(uuid))
      this.IconAction(this.isInstanceRunning(uuid) ? $r('sys.symbol.pause_fill') : $r('sys.symbol.play_fill'),
        this.isInstanceRunning(uuid), (): void => {
          this.toggleInstance(uuid)
        })
      this.IconAction($r('sys.symbol.square_and_pencil'), false, (): void => {
        HMRouterMgr.push({ pageUrl: 'EditPage', param: { uuid: uuid, unsafe: true } })
      })
    }
    .height(50)
    .width('100%')
    .padding({ left: 8, right: 8 })
    .borderRadius(8)
    .backgroundColor(uuid === this.selectedUuid() ? $r('sys.color.interactive_select') : Color.Transparent)
    .onClick(() => {
      this.selectInstance(uuid)
    })
  }

  @Builder
  InstancesPanel() {
    Column({ space: 8 }) {
      Row() {
        Column({ space: 1 }) {
          Text('实例')
            .fontSize(15)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('sys.color.font_primary'))
          Text(`${AppManager.data.configIds.length} 个配置`)
            .fontSize(11)
            .fontColor($r('sys.color.font_secondary'))
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      if (AppManager.data.configIds.length === 0) {
        Row({ space: 8 }) {
          SymbolGlyph($r('sys.symbol.plus_circle'))
            .fontSize(18)
            .fontColor([$r('sys.color.font_secondary')])
          Text('暂无实例')
            .fontSize(13)
            .fontColor($r('sys.color.font_secondary'))
        }
        .width('100%')
        .height(54)
        .padding({ left: 12, right: 12 })
        .justifyContent(FlexAlign.Center)
        .borderRadius(8)
        .backgroundColor($r('sys.color.comp_background_primary'))
      } else {
        Column({ space: 2 }) {
          ForEach(AppManager.data.configIds, (uuid: string) => {
            this.InstanceRow(uuid)
          }, (uuid: string) => uuid)
        }
        .width('100%')
        .padding({ top: 4, bottom: 4 })
        .borderRadius(8)
        .backgroundColor($r('sys.color.comp_background_primary'))
      }
    }
    .width('100%')
  }

  @Builder
  ToolsPanel() {
    Column({ space: 8 }) {
      this.SectionTitle('工具', '远端、日志与社区')
      Column() {
        this.GroupedCommandRow($r('sys.symbol.local_and_rectangle'), '跨设备控制', this.remoteDetailText(), true, true,
          (): void => {
            HMRouterMgr.push({ pageUrl: 'RemoteControlPage' })
          })
        this.GroupedCommandRow($r('sys.symbol.list_bullet_square'), '运行日志',
          `${AppManager.easytier.appLogs.totalCount()} 条`, false, true, (): void => {
          this.openLogsSheet()
        })
        this.GroupedCommandRow($r('sys.symbol.qrcode'), '分享配置',
          this.selectedUuid() ? this.selectedInstanceName() : '先选择实例', true, true, (): void => {
            this.qr()
          })
        this.GroupedCommandRow($r('sys.symbol.star_fill'), '收藏实例', this.favoriteConfigName(), false, true,
          (): void => {
            this.toggleFavorite()
          })
        this.GroupedCommandRow($r('sys.symbol.message_on_message'), '社区群', `${this.qqGroupCount()} 个入口`, false,
          false, (): void => {
            this.openQQGroup()
          })
      }
      .width('100%')
      .borderRadius(8)
      .backgroundColor($r('sys.color.comp_background_primary'))

      Column({ space: 0 }) {
        this.InfoLine('远端设备', this.remoteDeviceText())
        this.InfoLine('当前版本', this.versionText())
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 6, bottom: 6 })
      .borderRadius(8)
      .backgroundColor($r('sys.color.comp_background_primary'))
    }
    .width('100%')
  }

  @Builder
  HomePageTab(index: number, title: string, icon: Resource) {
    Row({ space: 5 }) {
      SymbolGlyph(icon)
        .fontSize(15)
        .fontColor([this.isHomePageVisible(index) ? '#FFFFFFFF' : $r('sys.color.font_secondary')])
      Text(title)
        .fontSize(12)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.isHomePageVisible(index) ? '#FFFFFFFF' : $r('sys.color.font_secondary'))
        .maxLines(1)
    }
    .height(32)
    .padding({ left: 11, right: 11 })
    .borderRadius(16)
    .backgroundColor(this.isHomePageVisible(index) ? $r('sys.color.interactive_active') : Color.Transparent)
    .onClick(() => {
      this.switchHomePage(index)
    })
  }

  @Builder
  HomeTopSwitcher() {
    if (this.visiblePageCount() < 3) {
      Row() {
        Row({ space: 3 }) {
          this.HomePageTab(0, '控制', $r('sys.symbol.play_circle'))
          this.HomePageTab(1, '实例', $r('sys.symbol.key_shield'))
          this.HomePageTab(2, '工具', $r('sys.symbol.square_fill_grid_2x2'))
        }
        .height(36)
        .padding({ left: 3, right: 3 })
        .borderRadius(18)
        .backgroundColor($r('sys.color.comp_background_primary'))
      }
      .width('100%')
      .height(44)
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
    }
  }

  @Builder
  ControlHomePage() {
    Scroll(this.controlScroller) {
      Column({ space: 14 }) {
        Column()
          .width('100%')
          .height(this.pageTopInset())
        this.ControlPanel()
        Column()
          .width('100%')
          .height(this.pageBottomInset())
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .padding({ left: this.pageHorizontalPadding(), right: this.pageHorizontalPadding() })
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
    .align(Alignment.Top)
  }

  @Builder
  LocalHomePage() {
    Scroll(this.localActionScroller) {
      Column({ space: 14 }) {
        Column()
          .width('100%')
          .height(this.pageTopInset())
        this.InstancesPanel()
        Column()
          .width('100%')
          .height(this.pageBottomInset())
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .padding({ left: this.pageHorizontalPadding(), right: this.pageHorizontalPadding() })
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
    .align(Alignment.Top)
  }

  @Builder
  CrossHomePage() {
    Scroll(this.crossActionScroller) {
      Column({ space: 14 }) {
        Column()
          .width('100%')
          .height(this.pageTopInset())
        this.ToolsPanel()
        Column()
          .width('100%')
          .height(this.pageBottomInset())
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .padding({ left: this.pageHorizontalPadding(), right: this.pageHorizontalPadding() })
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
    .align(Alignment.Top)
  }

  @Builder
  HomePageSwiper() {
    Swiper(this.homeSwiperController) {
      this.ControlHomePage()
      this.LocalHomePage()
      this.CrossHomePage()
    }
    .width('100%')
    .height('100%')
    .index(this.effectiveHomePageIndex())
    .displayCount(this.visiblePageCount())
    .itemSpace(this.isExpandedHomeLayout() ? 8 : 0)
    .cachedCount(1, false)
    .loop(false)
    .indicator(false)
    .onChange((index: number) => {
      this.homePageIndex = Math.max(0, Math.min(index, this.maxHomePageIndex()))
    })
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
              bundleName: 'top.frankhan.easytier',
              abilityName: 'EntryFormAbility',
              parameters: {
                'ohos.extra.param.key.form_dimension': 1,
                'ohos.extra.param.key.form_name': comp_type.toLowerCase() + '_widget',
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
