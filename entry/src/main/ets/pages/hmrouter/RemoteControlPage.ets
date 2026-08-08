import { HMRouter, HMRouterMgr } from '@hadss/hmrouter'
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
    .fontColor(active ? $r('sys.color.brand_font') : $r('sys.color.font_secondary'))
    .padding({ left: 8, right: 8, top: 4, bottom: 4 })
    .borderRadius(10)
    .backgroundColor(active ? $r('sys.color.brand') : $r('sys.color.comp_background_secondary'))
}

@Builder
function remoteEmptyCard(icon: Resource, text: string) {
  Column({ space: 8 }) {
    SymbolGlyph(icon)
      .fontSize(24)
      .fontColor([$r('sys.color.font_secondary')])
    Text(text)
      .fontSize(15)
      .fontColor($r('sys.color.font_secondary'))
  }
  .height(112)
  .justifyContent(FlexAlign.Center)
  .alignItems(HorizontalAlign.Center)
  .remoteCardStyle()
}

@Extend(Column)
function remoteCardStyle() {
  .width('100%')
  .borderRadius(18)
  .backgroundColor($r('sys.color.comp_background_primary'))
  .shadow({
    radius: 7,
    color: '#1F000000'
  })
    .padding(12)
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
  private summaryRefreshTimer: number = -1
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
      return
    }
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext
    IapService.ensureEntitlementLoaded(context).then((owned: boolean) => {
      if (!owned) {
        sendToast('请先在主页解锁跨设备控制', $r('sys.symbol.exclamationmark_circle'), 1)
        HMRouterMgr.pop()
      }
    }).catch(() => {
    })
  }

  aboutToAppear(): void {
    this.enforceEntitlement()
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
    EventHelper.emitterOff(REMOTE_MANAGE_CONNECTION_EVENT, this.remoteConnectionCallback)
    EventHelper.emitterOff(REMOTE_MANAGE_SUMMARY_DIRTY_EVENT, this.remoteSummaryDirtyCallback)
    this.stopSummaryRefreshTimer()
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
    if (!RemoteManageService.connected) {
      this.connected = false
      this.summaryView.clear()
      return
    }
    try {
      this.summaryView.apply(await RemoteManageService.requestSummary())
      this.connected = true
    } catch (error) {
      this.connected = false
      this.summaryView.clear()
      sendToast('刷新远端状态失败', $r('sys.symbol.exclamationmark_circle'), 1)
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
      pageUrl: 'RemoteStatusPage',
      param: {
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
    ListItemGroup({ header: remoteGroupHeader('设备') }) {
      if (this.devices.length === 0) {
        ListItem() {
          Column() {
            Text('暂无可用设备')
              .fontSize(16)
              .fontColor($r('sys.color.font_secondary'))
          }
          .remoteCardStyle()
        }
        .margin({ bottom: 10 })
      } else {
        ForEach(this.devices, (device: RemoteDeviceLite) => {
          ListItem() {
            Row() {
              Column() {
                Text(device.deviceName)
                  .fontSize(16)
                  .fontColor($r('sys.color.font_primary'))
                  .maxLines(1)
                Text(device.networkId ?? device.deviceId)
                  .fontSize(11)
                  .fontColor($r('sys.color.font_secondary'))
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .margin({ top: 3 })
              }
              .layoutWeight(1)
              .alignItems(HorizontalAlign.Start)

              if (this.selectedDeviceId === (device.networkId ?? device.deviceId)) {
                SymbolGlyph($r('sys.symbol.checkmark_circle_fill'))
                  .fontColor([$r('sys.color.brand')])
                  .fontSize(20)
              }
            }
            .width('100%')
            .height(58)
            .padding({ left: 12, right: 12 })
            .borderRadius(18)
            .backgroundColor($r('sys.color.comp_background_primary'))
            .shadow({
              radius: 7,
              color: '#1F000000'
            })
            .onClick(() => this.selectDevice(device))
          }
          .margin({ bottom: 10 })
        }, (device: RemoteDeviceLite) => device.networkId ?? device.deviceId)
      }
      ListItem() {
        Row({ space: 10 }) {
          Button(this.connected ? '断开' : (this.connecting ? '连接中' : '连接'),
            { type: ButtonType.Normal, buttonStyle: ButtonStyleMode.EMPHASIZED, role: ButtonRole.NORMAL })
            .layoutWeight(1)
            .borderRadius(13)
            .enabled(!this.connecting)
            .onClick(() => {
              if (this.connected) {
                this.disconnect()
              } else {
                this.connect()
              }
            })
          Button('刷新设备', { type: ButtonType.Normal, buttonStyle: ButtonStyleMode.NORMAL, role: ButtonRole.NORMAL })
            .layoutWeight(1)
            .borderRadius(13)
            .onClick(() => this.refreshDevices())
        }
        .width('100%')
      }
      .margin({ bottom: 10 })
    }
  }

  @Builder
  private runtimeSummary() {
    ListItemGroup({ header: remoteGroupHeader('运行状态') }) {
      ListItem() {
        Column() {
          Column({ space: 10 }) {
            Row({ space: 8 }) {
              remoteInfoPill(this.connected ? '已连接' : '未连接', this.connected)
              if (this.summaryView.deviceName.length > 0) {
                remoteInfoPill(this.summaryView.deviceName)
              }
              if (this.summaryView.coreVersion.length > 0) {
                remoteInfoPill(`Core ${this.summaryView.coreVersion}`)
              }
            }
            .width('100%')
            .alignItems(VerticalAlign.Center)

            Row() {
                Text('配置数量')
                  .fontSize(14)
                  .fontColor($r('sys.color.font_secondary'))
                Blank()
                Text(this.connected ? `${this.summaryView.configCount}` : '--')
                  .fontSize(16)
                  .fontColor($r('sys.color.font_primary'))
              }
            .width('100%')
            Row() {
                Text('运行配置')
                  .fontSize(14)
                  .fontColor($r('sys.color.font_secondary'))
                Blank()
                Text(this.connected ? `${this.summaryView.runningCount}` : '--')
                  .fontSize(16)
                  .fontColor($r('sys.color.font_primary'))
              }
            .width('100%')
            Row() {
                Text('运行时长')
                  .fontSize(14)
                  .fontColor($r('sys.color.font_secondary'))
                Blank()
                Text(this.connected ? this.summaryView.runtimeDurationText : '--')
                  .fontSize(16)
                  .fontColor($r('sys.color.font_primary'))
              }
            .width('100%')
              Row() {
                  Text('内存占用')
                    .fontSize(14)
                  .fontColor($r('sys.color.font_secondary'))
                Blank()
                Text(this.connected ? this.summaryView.memoryUsageText : '--')
                  .fontSize(16)
                  .fontColor($r('sys.color.font_primary'))
                }
              .width('100%')
            }
            .width('100%')
          }
        .remoteCardStyle()
      }
      .margin({ bottom: 10 })
      if (this.summaryView.runningCount > 0) {
        LazyForEach(this.summaryView.runtimes, (instance: RemoteRuntimeRowModel) => {
          ListItem() {
            Column({ space: 6 }) {
              Row({ space: 8 }) {
                remoteInfoPill('运行中', true)
                Text(instance.displayName)
                  .fontSize(14)
                  .fontColor($r('sys.color.font_primary'))
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .layoutWeight(1)
              }
              .width('100%')
              Row() {
                Text(instance.virtualIpv4)
                  .fontSize(12)
                  .fontColor($r('sys.color.font_secondary'))
                Blank()
                Text(`节点 ${instance.peerCount} · 路由 ${instance.routeCount}`)
                  .fontSize(12)
                  .fontColor($r('sys.color.font_secondary'))
              }
              .width('100%')
              Button('查看状态', {
                type: ButtonType.Normal,
                buttonStyle: ButtonStyleMode.NORMAL,
                role: ButtonRole.NORMAL
              })
                .width('100%')
                .height(36)
                .borderRadius(12)
                .onClick(() => this.openStatus(instance))
            }
            .remoteCardStyle()
          }
          .margin({ bottom: 10 })
        }, (instance: RemoteRuntimeRowModel) => instance.rowKey)
      } else if (this.connected) {
        ListItem() {
          remoteEmptyCard($r('sys.symbol.pause_circle'), '当前没有运行中的远端配置')
        }
        .margin({ bottom: 10 })
      }
    }
  }

  @Builder
  private configList() {
    ListItemGroup({ header: remoteGroupHeader('本机配置') }) {
      if (this.localConfigs.length === 0) {
        ListItem() {
          remoteEmptyCard($r('sys.symbol.doc'), '本机暂无可下发配置')
        }
        .margin({ bottom: 10 })
      } else {
        ForEach(this.localConfigs, (config: StoredConfigMetaLite) => {
          ListItem() {
            Column({ space: 10 }) {
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
                  .borderRadius(13)
                  .enabled(this.connected && this.summaryView.runningCount === 0 &&
                    this.deployingConfigId.length === 0)
                  .onClick(() => this.deployLocalConfig(config))
                Button('编辑', {
                  type: ButtonType.Normal,
                  buttonStyle: ButtonStyleMode.NORMAL,
                  role: ButtonRole.NORMAL
                })
                  .layoutWeight(1)
                  .borderRadius(13)
                  .onClick(() => this.editLocalConfig(config.configId))
                Button('复制', {
                  type: ButtonType.Normal,
                  buttonStyle: ButtonStyleMode.NORMAL,
                  role: ButtonRole.NORMAL
                })
                  .layoutWeight(1)
                  .borderRadius(13)
                  .onClick(() => this.copyLocalConfig(config.configId))
              }
              .width('100%')
            }
            .remoteCardStyle()
          }
          .margin({ bottom: 10 })
        }, (config: StoredConfigMetaLite) => config.configId)
      }
    }
  }

  @Builder
  private remoteSettings() {
    ListItemGroup({ header: remoteGroupHeader('受控端设置') }) {
      ListItem() {
        Row({ space: 8 }) {
          Button('运行与保活', {
            type: ButtonType.Normal,
            buttonStyle: ButtonStyleMode.NORMAL,
            role: ButtonRole.NORMAL
          })
            .layoutWeight(1)
            .borderRadius(13)
            .onClick(() => this.openRemoteSetting('runtime', '运行与保活'))
          Button('高级设置', {
            type: ButtonType.Normal,
            buttonStyle: ButtonStyleMode.NORMAL,
            role: ButtonRole.NORMAL
          })
            .layoutWeight(1)
            .borderRadius(13)
            .onClick(() => this.openRemoteSetting('advanced', '高级设置'))
          Button('日志', {
            type: ButtonType.Normal,
            buttonStyle: ButtonStyleMode.NORMAL,
            role: ButtonRole.NORMAL
          })
            .layoutWeight(1)
            .borderRadius(13)
            .onClick(() => this.openRemoteSetting('logs', '日志与调试'))
        }
        .width('100%')
      }
      .margin({ bottom: 10 })
    }
  }

  build() {
    HdsNavigation() {
      List() {
        ListItem()
          .height(64)
        this.deviceSelector()
        this.runtimeSummary()
        this.configList()
        if (this.connected) {
          this.remoteSettings()
        }
        ListItem()
          .height(120)
      }
      .width('100%')
      .height('100%')
      .padding({ left: 15, right: 15 })
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
          value: this.connected && this.summaryView.runningCount > 0 ? [
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
