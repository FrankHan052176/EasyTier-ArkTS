import { HMLifecycleState, HMRouter, HMRouterMgr } from '@hadss/hmrouter'
import { common } from '@kit.AbilityKit'
import { IapService } from '../../services/iap/IapService'
import { HdsNavigation, HdsNavigationTitleMode, hdsMaterial, TitleBarStyleOptions } from '@kit.UIDesignKit'
import { LengthMetrics } from '@kit.ArkUI'
import { deviceInfo, emitter } from '@kit.BasicServicesKit'
import { AppManager } from '../../AppManager'
import { HdsMenuButton } from '../Components'
import {
  REMOTE_MANAGE_CONNECTION_EVENT,
  REMOTE_MANAGE_SUMMARY_DIRTY_EVENT,
  RemoteManageService
} from '../../services/remote/RemoteManageService'
import { RemoteDeviceLite } from '../../services/remote/RemoteManageTypes'
import {
  RemoteRuntimeRowModel,
  RemoteSummaryViewState
} from './remote/RemoteSummaryViewState'
import { sendToast } from '../../ToastUtil'
import { ConfigJson } from '../../config/schema/SchemaConfig'
import { EventHelper } from '../../util/EventHelper'
import {
  listStoredConfigs,
  StoredConfigMetaLite
} from '../../services/config/storage/StoredConfigService'

interface RemoteSummaryDirtyEventPayload {
  sessionKey?: string
}

interface RemoteDeviceSelectOption {
  value: string
}

class RemoteDeviceSelectOptionItem implements RemoteDeviceSelectOption {
  value: string

  constructor(value: string) {
    this.value = value
  }
}

function remoteTitleStyle(): TitleBarStyleOptions {
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
            mainTitleColor: $r('sys.color.font_primary'),
            subTitleColor: $r('sys.color.font_secondary')
          },
          menuStyle: {
            iconColor: $r('sys.color.font_primary')
          },
          backIconStyle: {
            iconColor: $r('sys.color.font_primary')
          }
        }
      },
      systemMaterialEffect: {
        materialType: hdsMaterial.MaterialType.ADAPTIVE,
        materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
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
          mainTitleColor: $r('sys.color.font_primary'),
          subTitleColor: $r('sys.color.font_secondary')
        },
        menuStyle: {
          iconColor: $r('sys.color.font_primary'),
          backgroundColor: $r('sys.color.background_primary')
        },
        backIconStyle: {
          iconColor: $r('sys.color.font_primary'),
          backgroundColor: $r('sys.color.background_primary')
        }
      }
    }
  }
}

@Builder
function remoteGroupHeader(title: string) {
  Text(title)
    .width('100%')
    .fontSize(14)
    .fontColor($r('sys.color.font_secondary'))
    .padding({ top: 10, left: 5, bottom: 3 })
}

@Builder
function remoteInfoPill(text: string, active: boolean = false) {
  Text(text)
    .fontSize(12)
    .fontColor(active ? $r('sys.color.brand') : $r('sys.color.font_secondary'))
    .padding({ left: 8, right: 8, top: 4, bottom: 4 })
    .borderRadius(10)
    .backgroundColor($r('sys.color.comp_background_tertiary'))
}

@Builder
function remoteEmptyCard(icon: Resource, text: string) {
  Row({ space: 10 }) {
    SymbolGlyph(icon)
      .fontSize(20)
      .fontColor([$r('sys.color.font_secondary')])
    Text(text)
      .fontSize(14)
      .fontColor($r('sys.color.font_secondary'))
  }
  .height(64)
  .padding({ left: 14, right: 14 })
  .alignItems(VerticalAlign.Center)
  .remoteCardStyle()
}

@Styles
function remoteCardStyle() {
  .width('100%')
  .borderRadius(16)
  .backgroundColor($r('sys.color.comp_background_primary'))
  .padding(14)
}

@HMRouter({ pageUrl: 'RemoteControlPage' })
@ComponentV2
export struct RemoteControlPage {
  @Local devices: RemoteDeviceLite[] = []
  @Local selectedDeviceId: string = ''
  @Local selectedDeviceName: string = ''
  @Local connecting: boolean = false
  @Local connected: boolean = RemoteManageService.connected
  @Local localConfigs: StoredConfigMetaLite[] = []
  @Local deployingConfigId: string = ''
  @Local stopping: boolean = false
  @Local summaryView: RemoteSummaryViewState = new RemoteSummaryViewState()
  @Local consoleAuthorized: boolean = IapService.isRemoteControlUnlocked()
  private summaryRefreshTimer: number = -1
  private summaryRefreshRunning: boolean = false
  private summaryRefreshPending: boolean = false
  private pageVisible: boolean = false
  private pageActivated: boolean = false
  private lifecycleOwner = HMRouterMgr.getCurrentLifecycleOwner()
  private backPressedCallback = (): boolean => {
    void RemoteManageService.disconnect()
    return false
  }
  private remoteConnectionCallback = (_data: emitter.EventData) => {
    this.connected = RemoteManageService.connected
    this.summaryView.apply(this.connected ? RemoteManageService.cachedSummary : undefined)
    this.refreshLocalConfigs()
  }
  private remoteSummaryDirtyCallback = (data: emitter.EventData) => {
    const payload = data.data as RemoteSummaryDirtyEventPayload
    if (!this.connected || (payload?.sessionKey && !RemoteManageService.isCurrentSession(payload.sessionKey))) {
      return
    }
    this.refreshSummary()
  }

  /** 跨设备控制为付费能力：非卡片入口进入时兜底校验 remote_control 权益 */
  private enforceEntitlement(): void {
    if (IapService.isRemoteControlUnlocked()) {
      this.consoleAuthorized = true
      this.activateConsole()
      return
    }
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext
    IapService.ensureEntitlementLoaded(context).then((owned: boolean) => {
      if (!this.pageVisible) {
        return
      }
      if (!owned) {
        this.closeUnauthorizedConsole()
        return
      }
      this.consoleAuthorized = true
      this.activateConsole()
    }).catch(() => {
      if (this.pageVisible) {
        this.closeUnauthorizedConsole()
      }
    })
  }

  aboutToAppear(): void {
    this.pageVisible = true
    this.lifecycleOwner?.removeObserver(HMLifecycleState.onBackPressed, this.backPressedCallback)
    this.lifecycleOwner?.addObserver(HMLifecycleState.onBackPressed, this.backPressedCallback)
    this.enforceEntitlement()
  }

  private activateConsole(): void {
    if (!this.pageVisible || this.pageActivated) {
      return
    }
    this.pageActivated = true
    EventHelper.emitterOff(REMOTE_MANAGE_CONNECTION_EVENT, this.remoteConnectionCallback)
    EventHelper.emitterOff(REMOTE_MANAGE_SUMMARY_DIRTY_EVENT, this.remoteSummaryDirtyCallback)
    EventHelper.emitterListener(REMOTE_MANAGE_CONNECTION_EVENT, this.remoteConnectionCallback)
    EventHelper.emitterListener(REMOTE_MANAGE_SUMMARY_DIRTY_EVENT, this.remoteSummaryDirtyCallback)
    this.connected = RemoteManageService.connected
    this.summaryView.apply(this.connected ? RemoteManageService.cachedSummary : undefined)
    this.refreshDevices()
    if (this.connected) {
      this.refreshSummary()
    }
    this.startSummaryRefreshTimer()
  }

  aboutToDisappear(): void {
    this.pageVisible = false
    this.pageActivated = false
    this.summaryRefreshPending = false
    EventHelper.emitterOff(REMOTE_MANAGE_CONNECTION_EVENT, this.remoteConnectionCallback)
    EventHelper.emitterOff(REMOTE_MANAGE_SUMMARY_DIRTY_EVENT, this.remoteSummaryDirtyCallback)
    this.lifecycleOwner?.removeObserver(HMLifecycleState.onBackPressed, this.backPressedCallback)
    this.stopSummaryRefreshTimer()
  }

  private closeUnauthorizedConsole(): void {
    this.consoleAuthorized = false
    void RemoteManageService.disconnect()
    sendToast('请先在主页解锁跨设备控制', $r('sys.symbol.exclamationmark_circle'), 1)
    HMRouterMgr.pop()
  }

  private startSummaryRefreshTimer(): void {
    if (this.summaryRefreshTimer >= 0) {
      return
    }
    this.summaryRefreshTimer = setInterval(() => {
      if (this.connected && RemoteManageService.connected) {
        this.refreshSummary()
      }
    }, 5000)
  }

  private stopSummaryRefreshTimer(): void {
    if (this.summaryRefreshTimer < 0) {
      return
    }
    clearInterval(this.summaryRefreshTimer)
    this.summaryRefreshTimer = -1
  }

  private async refreshDevices(): Promise<void> {
    const ok = await AppManager.permission.requestDistributePerm(false)
    if (!ok) {
      sendToast('缺少分布式权限', $r('sys.symbol.exclamationmark_circle'), 1)
      return
    }
    this.devices = RemoteManageService.listAvailableDevices(AppManager.content.deviceManager)
    if (!this.selectedDeviceId && this.devices.length > 0) {
      this.selectDevice(this.devices[0])
    }
  }

  private selectDevice(device: RemoteDeviceLite): void {
    if (this.connected) {
      return
    }
    this.selectedDeviceId = device.networkId ?? device.deviceId
    this.selectedDeviceName = device.deviceName
  }

  private currentDevice(): RemoteDeviceLite | undefined {
    return this.devices.find((device) => (device.networkId ?? device.deviceId) === this.selectedDeviceId)
  }

  @Computed
  get deviceSelectOptions(): RemoteDeviceSelectOption[] {
    return this.devices.map((device: RemoteDeviceLite) => {
      return new RemoteDeviceSelectOptionItem(device.deviceName)
    })
  }

  @Computed
  get selectedDeviceIndex(): number {
    const index = this.devices.findIndex((device: RemoteDeviceLite) => {
      return (device.networkId ?? device.deviceId) === this.selectedDeviceId
    })
    return index >= 0 ? index : 0
  }

  private async connect(): Promise<void> {
    const device = this.currentDevice()
    if (!device || !AppManager.content.context) {
      sendToast('请选择受控设备', $r('sys.symbol.exclamationmark_circle'), 1)
      return
    }
    this.connecting = true
    try {
      const summary = await RemoteManageService.connect(AppManager.content.context, device)
      this.summaryView.apply(summary)
      this.connected = true
      this.selectedDeviceId = device.networkId ?? ''
      this.selectedDeviceName = summary.deviceName ?? device.deviceName
      sendToast('远端已连接', $r('sys.symbol.checkmark_circle'), 1)
    } catch (error) {
      this.connected = false
      this.summaryView.clear()
      sendToast(`连接失败：${(error as Error).message}`, $r('sys.symbol.exclamationmark_circle'), 1)
    } finally {
      this.connecting = false
    }
  }

  private async disconnect(): Promise<void> {
    await RemoteManageService.disconnect()
    this.connected = false
    this.summaryView.clear()
  }

  private async refreshSummary(): Promise<void> {
    if (this.summaryRefreshRunning) {
      this.summaryRefreshPending = true
      return
    }
    if (!RemoteManageService.connected) {
      this.connected = false
      this.summaryView.clear()
      this.summaryRefreshPending = false
      return
    }
    this.summaryRefreshRunning = true
    try {
      this.summaryView.apply(await RemoteManageService.requestSummary())
      this.connected = true
    } catch (error) {
      await RemoteManageService.disconnect()
      this.connected = false
      this.summaryView.clear()
      sendToast('刷新远端状态失败', $r('sys.symbol.exclamationmark_circle'), 1)
    } finally {
      this.summaryRefreshRunning = false
      if (this.summaryRefreshPending) {
        this.summaryRefreshPending = false
        if (this.pageVisible && this.pageActivated && RemoteManageService.connected) {
          void this.refreshSummary()
        }
      }
    }
  }

  private currentConnectedDeviceName(): string {
    return this.summaryView.deviceName || RemoteManageService.currentDeviceName || this.selectedDeviceName
  }

  private refreshLocalConfigs(): void {
    AppManager.data.refreshConfigIds()
    this.localConfigs = listStoredConfigs()
  }

  private editLocalConfig(configId: string): void {
    HMRouterMgr.push({
      pageUrl: 'EditPage',
      param: {
        uuid: configId,
        unsafe: false
      }
    })
  }

  private copyLocalConfig(configId: string): void {
    const copiedId = AppManager.data.copyConfig(configId)
    this.refreshLocalConfigs()
    sendToast(copiedId ? '已复制本地配置' : '复制配置失败',
      copiedId ? $r('sys.symbol.checkmark_circle') : $r('sys.symbol.exclamationmark_circle'),
      copiedId ? 0 : 1)
  }

  private async deployLocalConfig(config: StoredConfigMetaLite): Promise<void> {
    const session = RemoteManageService.currentSessionKey
    if (!session || !this.connected) {
      sendToast('请先连接受控设备', $r('sys.symbol.exclamationmark_circle'), 1)
      return
    }
    if (this.summaryView.runningCount > 0) {
      sendToast('受控设备已有运行实例，请先停止', $r('sys.symbol.exclamationmark_circle'), 1)
      return
    }
    const source: ConfigJson | undefined = AppManager.easytier.getConfig(config.configId)
    if (!source) {
      sendToast('本地配置不存在', $r('sys.symbol.exclamationmark_circle'), 1)
      return
    }
    let oneShot: ConfigJson
    oneShot = JSON.parse(JSON.stringify(source)) as ConfigJson
    oneShot.instance_id = config.configId
    oneShot.hostname = this.currentConnectedDeviceName()
    this.deployingConfigId = config.configId
    try {
      const result = await RemoteManageService.deployConfigOnce(config.configId, oneShot, session)
      this.summaryView.apply(result.summary)
      sendToast(result.ok ? '一次性配置已下发并启动' : '受控实例未进入运行状态',
        result.ok ? $r('sys.symbol.checkmark_circle') : $r('sys.symbol.exclamationmark_circle'),
        result.ok ? 0 : 1)
    } catch (error) {
      sendToast(`下发失败：${(error as Error).message}`, $r('sys.symbol.exclamationmark_circle'), 1)
    } finally {
      this.deployingConfigId = ''
    }
  }

  private async stopRemoteInstance(): Promise<void> {
    const session = RemoteManageService.currentSessionKey
    const running = RemoteManageService.cachedSummary?.runtime.runningConfigs[0]
    if (!session || !running || this.stopping) {
      return
    }
    this.stopping = true
    try {
      const result = await RemoteManageService.stopConfig(running.instanceId, session)
      this.summaryView.apply(result.summary)
      sendToast(result.ok ? '受控实例已停止' : '停止受控实例失败',
        result.ok ? $r('sys.symbol.checkmark_circle') : $r('sys.symbol.exclamationmark_circle'),
        result.ok ? 0 : 1)
    } catch (error) {
      sendToast(`停止失败：${(error as Error).message}`, $r('sys.symbol.exclamationmark_circle'), 1)
    } finally {
      this.stopping = false
    }
  }

  private openStatus(instance: RemoteRuntimeRowModel): void {
    const session = RemoteManageService.currentSessionKey
    if (!session) {
      return
    }
    HMRouterMgr.push({
      pageUrl: 'StatusPage',
      param: {
        source: 'remote',
        configId: instance.instanceId,
        title: instance.displayName || instance.instanceId,
        remoteSessionId: session,
        remoteDeviceName: this.currentConnectedDeviceName()
      }
    })
  }

  private openRemoteSetting(category: string, title: string): void {
    const session = RemoteManageService.currentSessionKey
    if (!session) {
      return
    }
    HMRouterMgr.push({
      pageUrl: 'RemoteSettingPage',
      param: {
        category,
        title,
        remoteSessionId: session,
        remoteDeviceName: this.currentConnectedDeviceName()
      }
    })
  }

  @Builder
  private deviceSelector() {
    ListItemGroup({ header: remoteGroupHeader('受控设备') }) {
      if (this.devices.length === 0) {
        ListItem() {
          remoteEmptyCard($r('sys.symbol.superdevice'), '暂无可用设备，请确认设备在线')
        }
        .margin({ bottom: 8 })
      } else {
        ListItem() {
          Column({ space: 10 }) {
            Row({ space: 8 }) {
              SymbolGlyph(this.connected ? $r('sys.symbol.checkmark_circle_fill') :
                $r('sys.symbol.superdevice'))
                .fontSize(20)
                .fontColor([this.connected ? $r('sys.color.brand') : $r('sys.color.font_secondary')])
              Column({ space: 2 }) {
                Text(this.connected ? '协同连接已建立' : '选择同账号在线设备')
                  .fontSize(14)
                  .fontColor($r('sys.color.font_primary'))
                Text(this.connected ? '可查看状态、下发一次性配置并管理运行实例' : '连接前不会读取对端配置')
                  .fontSize(12)
                  .fontColor($r('sys.color.font_secondary'))
                  .maxLines(2)
              }
              .layoutWeight(1)
              .alignItems(HorizontalAlign.Start)
              remoteInfoPill(this.connected ? '已连接' : '未连接', this.connected)
            }
            .width('100%')

            Select(this.deviceSelectOptions)
              .selected(this.selectedDeviceIndex)
              .value(this.selectedDeviceName || this.devices[this.selectedDeviceIndex].deviceName)
              .width('100%')
              .height(42)
              .controlSize(ControlSize.SMALL)
              .font({ size: 14, weight: FontWeight.Medium })
              .fontColor($r('sys.color.font_primary'))
              .selectedOptionBgColor($r('sys.color.brand'))
              .selectedOptionFontColor('#FFFFFFFF')
              .optionBgColor($r('sys.color.comp_background_primary'))
              .optionFontColor($r('sys.color.font_primary'))
              .menuBackgroundColor($r('sys.color.comp_background_primary'))
              .borderRadius(12)
              .enabled(!this.connected)
              .opacity(this.connected ? 0.72 : 1)
              .onSelect((index: number) => {
                if (!this.connected && index >= 0 && index < this.devices.length) {
                  this.selectDevice(this.devices[index])
                }
              })

            Row({ space: 8 }) {
              Button(this.connected ? '断开连接' : (this.connecting ? '连接中' : '连接此设备'), {
                type: ButtonType.Normal,
                buttonStyle: this.connected ? ButtonStyleMode.NORMAL : ButtonStyleMode.EMPHASIZED,
                role: this.connected ? ButtonRole.ERROR : ButtonRole.NORMAL
              })
                .layoutWeight(1)
                .height(40)
                .borderRadius(12)
                .enabled(!this.connecting)
                .onClick(() => {
                  if (this.connected) {
                    void this.disconnect()
                  } else {
                    void this.connect()
                  }
                })
              Button({ type: ButtonType.Circle, stateEffect: true }) {
                SymbolGlyph($r('sys.symbol.arrow_2_circlepath'))
                  .fontSize(19)
              }
              .width(40)
              .height(40)
              .buttonStyle(ButtonStyleMode.NORMAL)
              .accessibilityText('刷新设备')
              .onClick(() => this.refreshDevices())
            }
            .width('100%')
          }
          .remoteCardStyle()
        }
        .margin({ bottom: 8 })
      }
    }
  }

  @Builder
  private summaryMetric(label: string, value: string) {
    Column({ space: 3 }) {
      Text(value)
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('sys.color.font_primary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      Text(label)
        .fontSize(11)
        .fontColor($r('sys.color.font_secondary'))
    }
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private runtimeSummary() {
    ListItemGroup({ header: remoteGroupHeader('运行状态') }) {
      ListItem() {
        Column({ space: 12 }) {
          Row() {
            Text('Core')
              .fontSize(12)
              .fontColor($r('sys.color.font_secondary'))
            Blank()
            Text(this.summaryView.coreVersion || '版本未知')
              .fontSize(12)
              .fontColor($r('sys.color.font_secondary'))
          }
          .width('100%')
          Row({ space: 12 }) {
            this.summaryMetric('配置', `${this.summaryView.configCount}`)
            this.summaryMetric('运行中', `${this.summaryView.runningCount}`)
            this.summaryMetric('运行时长', this.summaryView.runtimeDurationText)
            this.summaryMetric('内存', this.summaryView.memoryUsageText)
          }
          .width('100%')
        }
            .width('100%')
        .remoteCardStyle()
      }
      .margin({ bottom: 8 })
      if (this.summaryView.runningCount > 0) {
        LazyForEach(this.summaryView.runtimes, (instance: RemoteRuntimeRowModel) => {
          ListItem() {
            Row({ space: 12 }) {
              SymbolGlyph($r('sys.symbol.checkmark_circle_fill'))
                .fontSize(20)
                .fontColor([$r('sys.color.brand')])
              Column({ space: 3 }) {
                Text(instance.displayName || '未命名实例')
                  .fontSize(14)
                  .fontWeight(FontWeight.Medium)
                  .fontColor($r('sys.color.font_primary'))
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                Text(`${instance.virtualIpv4} · 节点 ${instance.peerCount} · 路由 ${instance.routeCount}`)
                  .fontSize(12)
                  .fontColor($r('sys.color.font_secondary'))
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
              }
              .layoutWeight(1)
              .alignItems(HorizontalAlign.Start)
              Text('运行中')
                .fontSize(12)
                .fontColor($r('sys.color.brand'))
              SymbolGlyph($r('sys.symbol.chevron_forward'))
                .fontSize(16)
                .fontColor([$r('sys.color.font_secondary')])
            }
            .height(58)
            .padding({ left: 14, right: 12 })
            .remoteCardStyle()
            .onClick(() => this.openStatus(instance))
          }
          .margin({ bottom: 8 })
        }, (instance: RemoteRuntimeRowModel) => instance.rowKey)
      } else {
        ListItem() {
          remoteEmptyCard($r('sys.symbol.pause_circle'), '当前没有运行中的远端配置')
        }
        .margin({ bottom: 8 })
      }
    }
  }

  @Builder
  private configList() {
    ListItemGroup({ header: remoteGroupHeader('下发本机配置') }) {
      if (this.localConfigs.length === 0) {
        ListItem() {
          remoteEmptyCard($r('sys.symbol.doc'), '本机暂无可下发配置')
        }
        .margin({ bottom: 8 })
      } else {
        ForEach(this.localConfigs, (config: StoredConfigMetaLite) => {
          ListItem() {
            Column({ space: 9 }) {
              Row() {
                Column() {
                  Text(config.displayName || config.configId)
                    .fontSize(16)
                    .fontColor($r('sys.color.font_primary'))
                    .maxLines(1)
                  Text(config.configId)
                    .fontSize(11)
                    .fontColor($r('sys.color.font_secondary'))
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .margin({ top: 3 })
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Start)
                if (this.deployingConfigId === config.configId) {
                  remoteInfoPill('下发中', true)
                }
              }
              .width('100%')

              Row({ space: 8 }) {
                Button('下发并启动', {
                  type: ButtonType.Normal,
                  buttonStyle: ButtonStyleMode.EMPHASIZED,
                  role: ButtonRole.NORMAL
                })
                  .layoutWeight(1)
                  .height(38)
                  .borderRadius(12)
                  .enabled(this.connected && this.summaryView.runningCount === 0 &&
                    this.deployingConfigId.length === 0)
                  .onClick(() => this.deployLocalConfig(config))
                Button('编辑', {
                  type: ButtonType.Normal,
                  buttonStyle: ButtonStyleMode.NORMAL,
                  role: ButtonRole.NORMAL
                })
                  .layoutWeight(1)
                  .height(38)
                  .borderRadius(12)
                  .onClick(() => this.editLocalConfig(config.configId))
                Button('复制', {
                  type: ButtonType.Normal,
                  buttonStyle: ButtonStyleMode.NORMAL,
                  role: ButtonRole.NORMAL
                })
                  .layoutWeight(1)
                  .height(38)
                  .borderRadius(12)
                  .onClick(() => this.copyLocalConfig(config.configId))
              }
              .width('100%')
            }
            .remoteCardStyle()
          }
          .margin({ bottom: 8 })
        }, (config: StoredConfigMetaLite) => config.configId)
      }
    }
  }

  @Builder
  private remoteSettings() {
    ListItemGroup({ header: remoteGroupHeader('受控端设置') }) {
      ListItem() {
        Column() {
          this.remoteSettingEntry($r('sys.symbol.arrow_up_and_down_square_portrait'), '运行与保活',
            this.summaryView.runtimeModeLabel,
            () => this.openRemoteSetting('runtime', '运行与保活'))
          Divider().color($r('sys.color.comp_divider')).margin({ left: 40 })
          this.remoteSettingEntry($r('sys.symbol.network_acceleration'), '高级设置',
            this.summaryView.devMode ? '高级模式已开启' : '网络与 DNS',
            () => this.openRemoteSetting('advanced', '高级设置'))
          Divider().color($r('sys.color.comp_divider')).margin({ left: 40 })
          this.remoteSettingEntry($r('sys.symbol.doc'), '日志与调试',
            this.summaryView.coreLog || this.summaryView.debugLog ? '日志记录已开启' : '日志记录已关闭',
            () => this.openRemoteSetting('logs', '日志与调试'))
        }
        .width('100%')
        .remoteCardStyle()
      }
      .margin({ bottom: 8 })
    }
  }

  @Builder
  private remoteSettingEntry(icon: Resource, title: string, subtitle: string, action: () => void) {
    Row({ space: 10 }) {
      SymbolGlyph(icon)
        .fontSize(18)
        .fontColor([$r('sys.color.font_secondary')])
      Column({ space: 2 }) {
        Text(title)
          .fontSize(14)
          .fontColor($r('sys.color.font_primary'))
        Text(subtitle)
          .fontSize(11)
          .fontColor($r('sys.color.font_secondary'))
          .maxLines(1)
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      SymbolGlyph($r('sys.symbol.chevron_forward'))
        .fontSize(16)
        .fontColor([$r('sys.color.font_secondary')])
    }
    .width('100%')
    .height(52)
    .onClick(action)
  }

  build() {
    HdsNavigation() {
      List() {
        ListItem()
          .height(56)
        this.deviceSelector()
        if (this.connected) {
          this.runtimeSummary()
        }
        this.configList()
        if (this.connected) {
          this.remoteSettings()
        }
        ListItem()
          .height(80)
      }
      .width('100%')
      .height('100%')
      .padding({ left: 15, right: 15 })
      .enabled(this.consoleAuthorized)
      .scrollBar(BarState.Auto)
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      .scrollBar(BarState.Off)
    }
    .titleBar({
      style: remoteTitleStyle(),
      content: {
          title: {
            mainTitle: '跨端控制',
            subTitle: this.connected ? this.currentConnectedDeviceName() : '选择受控设备'
          },
        menu: {
          value: !this.consoleAuthorized ? [] : this.connected && this.summaryView.runningCount > 0 ? [
            HdsMenuButton(this.stopping ? '停止中' : '停止', $r('sys.symbol.stop_circle'), () => {
              this.stopRemoteInstance()
            }),
            HdsMenuButton('刷新', $r('sys.symbol.arrow_2_circlepath'), () => {
              this.refreshSummary()
            })
          ] : [
            HdsMenuButton('刷新', $r('sys.symbol.arrow_2_circlepath'), () => {
              if (this.connected) {
                this.refreshSummary()
              } else {
                this.refreshDevices()
              }
              this.refreshLocalConfigs()
            })
          ]
        }
      }
    })
    .mode(NavigationMode.Stack)
    .titleMode(HdsNavigationTitleMode.MINI)
    .hideBackButton(false)
    .hideTitleBar(false)
    .height('100%')
    .width('100%')
    .backgroundColor($r('sys.color.background_secondary'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    }
}
