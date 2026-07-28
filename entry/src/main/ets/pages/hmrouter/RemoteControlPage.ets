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
import { RemoteActionSummaryResult, RemoteDeviceLite } from '../../services/remote/RemoteManageTypes'
import {
  RemoteConfigRowModel,
  RemoteRuntimeRowModel,
  RemoteSummaryViewState
} from './remote/RemoteSummaryViewState'
import { sendToast } from '../../ToastUtil'
import { syncWholeConfig } from '../../ConfigSyncUtil'
import { ConfigJson } from '../../config/schema/SchemaConfig'
import { listStoredConfigs, StoredConfigMetaLite } from '../../services/config/storage/StoredConfigService'
import { EventHelper } from '../../util/EventHelper'

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

function boolText(value: boolean): string {
  return value ? '开启' : '关闭'
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
  @Local showNewConfigSheet: boolean = false
  @Local showImportLocalSheet: boolean = false
  @Local newConfigName: string = 'EasyTier'
  @Local summaryView: RemoteSummaryViewState = new RemoteSummaryViewState()
  private summaryRefreshTimer: number = -1
  private remoteConnectionCallback = (_data: emitter.EventData) => {
    this.connected = RemoteManageService.connected
    this.summaryView.apply(this.connected ? RemoteManageService.cachedSummary : undefined)
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

  private applyRemoteActionResult(result: RemoteActionSummaryResult): void {
    if (!result.summary) {
      return
    }
    this.summaryView.apply(result.summary)
    this.connected = true
  }

  private isConfigRunning(configId: string): boolean {
    return this.summaryView.isConfigRunning(configId)
  }

  private async waitConfigRunningState(configId: string, expectedRunning: boolean): Promise<void> {
    for (let index = 0; index < 6; index++) {
      if (this.isConfigRunning(configId) === expectedRunning) {
        return
      }
      await new Promise<void>((resolve) => {
        setTimeout(() => {
          resolve()
        }, 600)
      })
      await this.refreshSummary()
    }
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

  private currentRemoteSession(): string | undefined {
    const session = RemoteManageService.currentSessionKey
    if (!session) {
      sendToast('远端未连接', $r('sys.symbol.exclamationmark_circle'), 1)
      return undefined
    }
    return session
  }

  private currentConnectedDeviceName(): string {
    return this.summaryView.deviceName || RemoteManageService.currentDeviceName || this.selectedDeviceName
  }

  private pushEditConfig(configId: string, displayName?: string): void {
    if (!RemoteManageService.currentSessionKey) {
      return
    }
    HMRouterMgr.push({
      pageUrl: 'EditPage',
      param: {
        uuid: configId,
        unsafe: false,
        source: 'remote',
        remoteSessionId: RemoteManageService.currentSessionKey,
        remoteDeviceName: this.currentConnectedDeviceName()
      }
    })
  }

  private editConfig(config: RemoteConfigRowModel): void {
    this.pushEditConfig(config.configId, config.displayName)
  }

  private async startConfig(config: RemoteConfigRowModel): Promise<void> {
    const session = this.currentRemoteSession()
    if (!session) {
      return
    }
    try {
      const result = await RemoteManageService.startConfig(config.configId, session)
      this.applyRemoteActionResult(result)
      sendToast(result.ok ? '已请求远端启动' : '远端启动失败',
        result.ok ? $r('sys.symbol.checkmark_circle') : $r('sys.symbol.exclamationmark_circle'), result.ok ? 0 : 1)
      if (result.ok) {
        await this.waitConfigRunningState(config.configId, true)
      } else {
        await this.refreshSummary()
      }
    } catch (error) {
      sendToast(`远端启动失败：${(error as Error).message}`, $r('sys.symbol.exclamationmark_circle'), 1)
    }
  }

  private async stopConfig(config: RemoteConfigRowModel): Promise<void> {
    const session = this.currentRemoteSession()
    if (!session) {
      return
    }
    try {
      const result = await RemoteManageService.stopConfig(config.configId, session)
      this.applyRemoteActionResult(result)
      sendToast(result.ok ? '已请求远端停止' : '远端停止失败',
        result.ok ? $r('sys.symbol.checkmark_circle') : $r('sys.symbol.exclamationmark_circle'), result.ok ? 0 : 1)
      if (result.ok) {
        await this.waitConfigRunningState(config.configId, false)
      } else {
        await this.refreshSummary()
      }
    } catch (error) {
      sendToast(`远端停止失败：${(error as Error).message}`, $r('sys.symbol.exclamationmark_circle'), 1)
    }
  }

  private confirmDeleteConfig(config: RemoteConfigRowModel): void {
    AlertDialog.show({
      title: '删除远端配置',
      message: `${config.displayName || config.configId}\n${config.configId}`,
      primaryButton: {
        value: '取消',
        action: () => {
        }
      },
      secondaryButton: {
        value: '删除',
        fontColor: Color.Red,
        action: () => {
          this.deleteConfig(config)
        }
      }
    })
  }

  private async deleteConfig(config: RemoteConfigRowModel): Promise<void> {
    const session = this.currentRemoteSession()
    if (!session) {
      return
    }
    try {
      const ok = await RemoteManageService.deleteConfig(config.configId, session)
      sendToast(ok ? '远端配置已删除' : '删除失败',
        ok ? $r('sys.symbol.checkmark_circle') : $r('sys.symbol.exclamationmark_circle'), ok ? 0 : 1)
      await this.refreshSummary()
    } catch (error) {
      sendToast(`删除失败：${(error as Error).message}`, $r('sys.symbol.exclamationmark_circle'), 1)
    }
  }

  private async exportRemoteConfig(config: RemoteConfigRowModel): Promise<void> {
    const session = this.currentRemoteSession()
    if (!session) {
      return
    }
    try {
      const remoteConfig = await RemoteManageService.getConfig(config.configId, session)
      if (!remoteConfig?.config) {
        sendToast('读取远端配置失败', $r('sys.symbol.exclamationmark_circle'), 1)
        return
      }
      const localConfig: ConfigJson = JSON.parse(JSON.stringify(remoteConfig.config)) as ConfigJson
      const localId = AppManager.data.safeUUID()
      localConfig.instance_id = localId
      const displayName = `${remoteConfig.displayName || config.configId} (远端)`
      if (syncWholeConfig(localId, displayName, localConfig)) {
        AppManager.data.refreshConfigIds()
        sendToast('已导出到本机配置', $r('sys.symbol.checkmark_circle'), 0)
      } else {
        sendToast('导出到本机失败', $r('sys.symbol.exclamationmark_circle'), 1)
      }
    } catch (error) {
      sendToast(`导出失败：${(error as Error).message}`, $r('sys.symbol.exclamationmark_circle'), 1)
    }
  }

  private async importLocalConfig(localId: string): Promise<void> {
    this.showImportLocalSheet = false
    const session = this.currentRemoteSession()
    if (!session) {
      return
    }
    if (!localId) {
      sendToast('请选择本机配置', $r('sys.symbol.exclamationmark_circle'), 1)
      return
    }
    try {
      const config: ConfigJson | undefined = AppManager.easytier.getConfig(localId)
      if (!config) {
        sendToast('读取本机配置失败', $r('sys.symbol.exclamationmark_circle'), 1)
        return
      }
      const name = AppManager.easytier.getConfigName(localId) ?? localId
      const imported = await RemoteManageService.importConfig(config, name, session)
      if (imported) {
        sendToast('已导入到远端', $r('sys.symbol.checkmark_circle'), 0)
        await this.refreshSummary()
        this.pushEditConfig(imported.configId, imported.displayName)
      } else {
        sendToast('导入远端失败', $r('sys.symbol.exclamationmark_circle'), 1)
      }
    } catch (error) {
      sendToast(`导入失败：${(error as Error).message}`, $r('sys.symbol.exclamationmark_circle'), 1)
    }
  }

  private async createRemoteConfig(): Promise<void> {
    this.showNewConfigSheet = false
    const session = this.currentRemoteSession()
    if (!session) {
      return
    }
    try {
      const created = await RemoteManageService.createDefaultConfig(this.newConfigName, session)
      if (!created) {
        sendToast('新建远端配置失败', $r('sys.symbol.exclamationmark_circle'), 1)
        return
      }
      await this.refreshSummary()
      this.pushEditConfig(created.configId, created.displayName)
    } catch (error) {
      sendToast(`新建失败：${(error as Error).message}`, $r('sys.symbol.exclamationmark_circle'), 1)
    }
  }

    private openSetting(category: string, title: string): void {
      const session = this.currentRemoteSession()
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

  private openStatus(config: RemoteConfigRowModel): void {
    const session = this.currentRemoteSession()
    if (!session) {
      return
    }
    HMRouterMgr.push({
      pageUrl: 'RemoteStatusPage',
      param: {
        configId: config.configId,
        title: config.displayName || config.configId,
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
    ListItemGroup({ header: remoteGroupHeader('远端配置') }) {
      ListItem() {
        Row({ space: 10 }) {
          Button('新建远端配置', { type: ButtonType.Normal, buttonStyle: ButtonStyleMode.EMPHASIZED, role: ButtonRole.NORMAL })
            .layoutWeight(1)
            .borderRadius(13)
            .enabled(this.connected)
            .onClick(() => {
              this.newConfigName = 'EasyTier'
              this.showNewConfigSheet = true
            })
          Button('导入本机配置', { type: ButtonType.Normal, buttonStyle: ButtonStyleMode.NORMAL, role: ButtonRole.NORMAL })
            .layoutWeight(1)
            .borderRadius(13)
            .enabled(this.connected)
            .onClick(() => {
              this.showImportLocalSheet = true
            })
        }
        .width('100%')
      }
      .margin({ bottom: 10 })

      if (this.summaryView.configCount === 0) {
        ListItem() {
          remoteEmptyCard($r('sys.symbol.doc'), '远端还没有配置')
        }
        .margin({ bottom: 10 })
      } else {
        LazyForEach(this.summaryView.configs, (config: RemoteConfigRowModel) => {
          ListItem() {
            Column() {
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
                  if (config.running) {
                    remoteInfoPill('运行中', true)
                  }
                }
                .width('100%')

                Row({ space: 8 }) {
                  Button('编辑', { type: ButtonType.Normal, buttonStyle: ButtonStyleMode.EMPHASIZED, role: ButtonRole.NORMAL })
                    .layoutWeight(1)
                    .borderRadius(13)
                    .onClick(() => this.editConfig(config))
                  Button(config.running ? '停止' : '启动',
                    { type: ButtonType.Normal, buttonStyle: ButtonStyleMode.NORMAL,
                      role: config.running ? ButtonRole.ERROR : ButtonRole.NORMAL })
                    .layoutWeight(1)
                    .borderRadius(13)
                    .onClick(() => {
                      if (config.running) {
                        this.stopConfig(config)
                      } else {
                        this.startConfig(config)
                      }
                    })
                  if (config.running) {
                    Button('状态', { type: ButtonType.Normal, buttonStyle: ButtonStyleMode.NORMAL, role: ButtonRole.NORMAL })
                      .layoutWeight(1)
                      .borderRadius(13)
                      .onClick(() => this.openStatus(config))
                  }
                }
                .width('100%')
                Row({ space: 8 }) {
                  Button('导出', { type: ButtonType.Normal, buttonStyle: ButtonStyleMode.NORMAL, role: ButtonRole.NORMAL })
                    .layoutWeight(1)
                    .borderRadius(13)
                    .onClick(() => this.exportRemoteConfig(config))
                  Button('删除', { type: ButtonType.Normal, buttonStyle: ButtonStyleMode.NORMAL, role: ButtonRole.ERROR })
                    .layoutWeight(1)
                    .borderRadius(13)
                    .onClick(() => this.confirmDeleteConfig(config))
                }
                .width('100%')
              }
              .width('100%')
            }
            .remoteCardStyle()
          }
          .margin({ bottom: 10 })
        }, (config: RemoteConfigRowModel) => config.configId)
      }
    }
  }

  @Builder
  private settingCategories() {
    ListItemGroup({ header: remoteGroupHeader('远端首选项') }) {
      this.settingCategoryRow('运行控制',
        `运行方案：${this.summaryView.runtimeModeLabel}`, 'runtime')
      this.settingCategoryRow('网络高级',
        `高级模式${boolText(this.summaryView.devMode)}`, 'advanced')
      this.settingCategoryRow('日志与调试',
        `内核日志${boolText(this.summaryView.coreLog)}，调试日志${boolText(this.summaryView.debugLog)}`,
        'logs')
      this.settingCategoryRow('权限',
        this.summaryView.distributePerm ? '分布式权限已授权' : '分布式权限未授权', 'permissions')
    }
  }

  @Builder
  private settingCategoryRow(title: string, subtitle: string, category: string) {
    ListItem() {
      Row() {
        Column() {
          Text(title)
            .fontSize(16)
            .fontColor($r('sys.color.font_primary'))
            .maxLines(1)
          Text(subtitle)
            .fontSize(12)
            .fontColor($r('sys.color.font_secondary'))
            .maxLines(1)
            .margin({ top: 3 })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        SymbolGlyph($r('sys.symbol.arrow_right'))
          .fontColor([$r('sys.color.font_primary')])
          .fontSize(16)
      }
      .width('100%')
      .height(58)
      .padding({ left: 12, right: 8 })
      .borderRadius(18)
      .backgroundColor($r('sys.color.comp_background_primary'))
      .shadow({
        radius: 7,
        color: '#1F000000'
      })
      .onClick(() => this.openSetting(category, title))
    }
    .margin({ bottom: 10 })
  }

    @Builder
    private ImportLocalConfigSheet() {
      HdsNavigation() {
        List() {
          ListItem()
            .height(64)
          if (listStoredConfigs().length === 0) {
            ListItem() {
              Column() {
                Text('本机暂无配置')
                  .fontSize(16)
                  .fontColor($r('sys.color.font_secondary'))
              }
              .remoteCardStyle()
            }
            .margin({ left: 15, right: 15, bottom: 10 })
          } else {
            ForEach(listStoredConfigs(), (config: StoredConfigMetaLite) => {
              ListItem() {
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
                  Button('导入', { type: ButtonType.Normal, buttonStyle: ButtonStyleMode.EMPHASIZED, role: ButtonRole.NORMAL })
                    .borderRadius(13)
                    .onClick(() => this.importLocalConfig(config.configId))
                }
                .width('100%')
                .height(58)
                .padding({ left: 12, right: 8 })
                .borderRadius(18)
                .backgroundColor($r('sys.color.comp_background_primary'))
                .shadow({
                  radius: 7,
                  color: '#1F000000'
                })
              }
              .margin({ left: 15, right: 15, bottom: 10 })
            }, (config: StoredConfigMetaLite) => config.configId)
          }
          ListItem()
            .height(120)
        }
        .width('100%')
        .height('100%')
        .scrollBar(BarState.Auto)
      }
      .titleBar({
        style: remoteTitleStyle(),
        content: {
          title: { mainTitle: '导入本机配置' },
          menu: {
            value: [HdsMenuButton('关闭', $r('sys.symbol.xmark'), () => {
              this.showImportLocalSheet = false
            })]
          }
        }
      })
      .mode(NavigationMode.Stack)
      .titleMode(HdsNavigationTitleMode.MODAL)
      .hideBackButton(true)
      .hideTitleBar(false)
      .backgroundColor($r('sys.color.background_secondary'))
    }

    @Builder
    private NewConfigSheet() {
      HdsNavigation() {
      Column({ space: 16 }) {
        Column().height(64)
        TextInput({ text: this.newConfigName, placeholder: 'EasyTier' })
          .width('90%')
          .height(48)
          .borderRadius(14)
          .backgroundColor($r('sys.color.comp_background_primary'))
          .onChange((value: string) => {
            this.newConfigName = value.length > 0 ? value : 'EasyTier'
          })
        Button('创建并编辑', { type: ButtonType.Normal, buttonStyle: ButtonStyleMode.EMPHASIZED, role: ButtonRole.NORMAL })
          .width('90%')
          .borderRadius(13)
          .onClick(() => this.createRemoteConfig())
      }
      .width('100%')
      .height('100%')
      .alignItems(HorizontalAlign.Center)
    }
    .titleBar({
      style: remoteTitleStyle(),
      content: {
        title: { mainTitle: '新建远端配置' },
        menu: {
          value: [HdsMenuButton('关闭', $r('sys.symbol.xmark'), () => {
            this.showNewConfigSheet = false
          })]
        }
      }
    })
    .mode(NavigationMode.Stack)
    .titleMode(HdsNavigationTitleMode.MODAL)
    .hideBackButton(true)
    .hideTitleBar(false)
    .backgroundColor($r('sys.color.background_secondary'))
  }

  build() {
    HdsNavigation() {
      List() {
        ListItem()
          .height(64)
        this.deviceSelector()
        this.runtimeSummary()
        if (this.connected) {
          this.configList()
          this.settingCategories()
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
          value: [HdsMenuButton('刷新', $r('sys.symbol.arrow_2_circlepath'), () => {
            this.refreshSummary()
          })]
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
      .bindSheet($$this.showNewConfigSheet, this.NewConfigSheet(), {
        height: SheetSize.MEDIUM,
        preferType: SheetType.CENTER,
        showClose: false,
        dragBar: false
      })
      .bindSheet($$this.showImportLocalSheet, this.ImportLocalConfigSheet(), {
        height: SheetSize.MEDIUM,
        preferType: SheetType.CENTER,
        showClose: false,
        dragBar: false
      })
    }
}
