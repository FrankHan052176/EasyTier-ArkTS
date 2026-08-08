import { HMRouter, HMRouterMgr } from '@hadss/hmrouter'
import { deviceInfo } from '@kit.BasicServicesKit'
import { HdsNavigation, HdsNavigationTitleMode, ScrollEffectType, HdsNavigationAttribute,
  hdsMaterial,
  TitleBarStyleOptions} from '@kit.UIDesignKit'
import { LengthMetrics } from '@kit.ArkUI'
import { AppManager, Sfp2vp, Svp2fp } from '../../AppManager'
import { DiscoverBall } from '../../components/status/DiscoverBall'
import { HdsMenuButton } from '../Components'
import { InstanceInfo, PeerInfo } from '../../class/InstanceInfo'
import { ConfigJson } from '../../config/schema/SchemaConfig'
import { NatTypeValue, natTypeToText, RuntimeInstanceState } from '../../types/runtime/RuntimeTypes'
import { Protocol, protocolBGColor, protocolColor } from '../../util/Conversion'
import { WindowUtil } from '../../WindowUtil'
import { harmonyShare } from '@kit.ShareKit'
import { buildShareData } from '../../util/ShareUtil'
import { RuntimeHealthSummary } from '../../EasyTierUtil'
import { RemoteStatusParam } from '../../types/navigation/PageParam'
import { RemoteManageService } from '../../services/remote/RemoteManageService'
import { sendToast } from '../../ToastUtil'

@HMRouter({ pageUrl: "StatusPage" })
@ComponentV2
export struct StatusPage {
  @Local uuid: string = ""
  @Local name: string = ""
  @Local config: ConfigJson | null = null;
  scroller: Scroller = new Scroller();
  @Local ip: string = ""
  @Local tcp_nat: NatTypeValue = NatTypeValue.Unknown
  @Local udp_nat: NatTypeValue = NatTypeValue.Unknown
  @Local rx_rate: number = 0
  @Local tx_rate: number = 0
  @Local rx_unit: string = "B/s"
  @Local tx_unit: string = "B/s"
  @Local runtimeHealthText: string = "正在确认运行状态"
  @Local runtimeHealthWarning: boolean = false
  @Local remoteMode: boolean = false
  @Local remoteDeviceName: string = ""
  @Local stopping: boolean = false
  @Local updateTimer: number = -1
  private remoteSessionId: string = ""
  private remoteRefreshRunning: boolean = false
  private remoteInstanceInfo: InstanceInfo = new InstanceInfo()
  private knockShareRegistered: boolean = false
  private gesturesShareRegistered: boolean = false

  @Computed
  get instanceInfo() {
    if (this.runtimeHealthWarning) {
      return undefined
    }
    return this.remoteMode ? this.remoteInstanceInfo.peers : AppManager.easytier.instanceInfos.get(this.uuid)?.peers
  }

  aboutToAppear(): void {
    const rawParam = HMRouterMgr.getCurrentParam()
    if (typeof rawParam === 'string') {
      this.setupLocalStatus(rawParam)
    } else {
      const remoteParam = rawParam as RemoteStatusParam
      if (remoteParam.source !== 'remote') {
        sendToast('状态页参数无效', $r('sys.symbol.exclamationmark_circle'), 1)
        setTimeout(() => HMRouterMgr.pop(), 0)
        return
      }
      this.setupRemoteStatus(remoteParam)
      if (!RemoteManageService.isCurrentSession(this.remoteSessionId)) {
        sendToast('远端连接已变化，请重新进入状态页', $r('sys.symbol.exclamationmark_circle'), 1)
        setTimeout(() => HMRouterMgr.pop(), 0)
        return
      }
    }
    this.startUpdateTimer()
    if (!this.remoteMode) {
      this.registerShareCallbacks()
    }
  }

  aboutToDisappear(): void {
    this.stopUpdateTimer()
    this.unregisterShareCallbacks()
  }

  private registerShareCallbacks(): void {
    if (!this.knockShareRegistered) {
      harmonyShare.on('knockShare', this.immersiveCallback);
      this.knockShareRegistered = true
    }
    if (!this.gesturesShareRegistered && deviceInfo.sdkApiVersion >= 20) {
      harmonyShare.on('gesturesShare', this.immersiveCallback);
      this.gesturesShareRegistered = true
    }
  }

  private unregisterShareCallbacks(): void {
    if (this.knockShareRegistered) {
      harmonyShare.off('knockShare', this.immersiveCallback);
      this.knockShareRegistered = false
    }
    if (this.gesturesShareRegistered) {
      harmonyShare.off('gesturesShare', this.immersiveCallback);
      this.gesturesShareRegistered = false
    }
  }

  private startUpdateTimer(): void {
    if (this.updateTimer >= 0) {
      return
    }
    this.updateRuntimeDisplay()
    this.updateTimer = setInterval(() => {
      this.updateRuntimeDisplay()
    }, this.remoteMode ? 3000 : 1000)
  }

  private stopUpdateTimer(): void {
    if (this.updateTimer < 0) {
      return
    }
    clearInterval(this.updateTimer)
    this.updateTimer = -1
  }

  private updateRuntimeDisplay(): void {
    if (this.remoteMode) {
      void this.refreshRemoteRuntime()
      return
    }
    AppManager.runtimeStats.refreshFromDisk()
    const health: RuntimeHealthSummary = AppManager.easytier.getRuntimeHealthSummary()
    this.runtimeHealthText = health.text
    this.runtimeHealthWarning = health.warning
    if (health.warning) {
      this.rx_rate = 0
      this.tx_rate = 0
      this.rx_unit = "B/s"
      this.tx_unit = "B/s"
      return
    }
    const instanceInfo = AppManager.easytier.instanceInfos.get(this.uuid)
    if (!instanceInfo) {
      return
    }
    if (instanceInfo.getDownloadRate() >= 0) {
      this.rx_rate = instanceInfo.getDownloadRate()
      this.rx_unit = instanceInfo.getDownloadRateUnit()
    }
    if (instanceInfo.getUploadRate() >= 0) {
      this.tx_rate = instanceInfo.getUploadRate()
      this.tx_unit = instanceInfo.getUploadRateUnit()
    }
    this.udp_nat = instanceInfo.udp_nat
    this.tcp_nat = instanceInfo.tcp_nat
    this.ip = instanceInfo.ip
  }

  private setupLocalStatus(uuid: string): void {
    this.remoteMode = false
    this.uuid = uuid
    this.name = AppManager.easytier.getConfigName(this.uuid) ?? "临时配置"
    this.config = AppManager.easytier.getConfig(this.uuid) ?? null
    this.ip = this.config?.dhcp ? "waiting" : (this.config?.virtual_ipv4 ?? "N/A")
  }

  private setupRemoteStatus(param: RemoteStatusParam): void {
    this.remoteMode = true
    this.uuid = param.configId
    this.name = param.title || param.configId
    this.remoteSessionId = param.remoteSessionId ?? RemoteManageService.currentSessionKey ?? ''
    this.remoteDeviceName = param.remoteDeviceName ?? RemoteManageService.currentDeviceName
    this.runtimeHealthText = '正在同步受控实例状态'
    this.ip = 'waiting'
  }

  private async refreshRemoteRuntime(): Promise<void> {
    if (this.remoteRefreshRunning) {
      return
    }
    if (!RemoteManageService.isCurrentSession(this.remoteSessionId)) {
      this.runtimeHealthWarning = true
      this.runtimeHealthText = '远端连接已断开'
      this.resetRemoteRates()
      return
    }
    this.remoteRefreshRunning = true
    try {
      const instance: RuntimeInstanceState | undefined =
        await RemoteManageService.getRuntimeInstance(this.uuid, this.remoteSessionId)
      if (!instance || !instance.running) {
        this.runtimeHealthWarning = true
        this.runtimeHealthText = '受控实例已停止'
        this.resetRemoteRates()
        return
      }
      this.remoteInstanceInfo.update(instance, true)
      this.runtimeHealthWarning = false
      this.runtimeHealthText = '受控实例运行正常'
      this.ip = this.remoteInstanceInfo.ip
      this.udp_nat = this.remoteInstanceInfo.udp_nat
      this.tcp_nat = this.remoteInstanceInfo.tcp_nat
      this.rx_rate = this.remoteInstanceInfo.getDownloadRate()
      this.rx_unit = this.remoteInstanceInfo.getDownloadRateUnit()
      this.tx_rate = this.remoteInstanceInfo.getUploadRate()
      this.tx_unit = this.remoteInstanceInfo.getUploadRateUnit()
    } catch (_) {
      this.runtimeHealthWarning = true
      this.runtimeHealthText = '远端状态暂不可用'
      this.resetRemoteRates()
    } finally {
      this.remoteRefreshRunning = false
    }
  }

  private resetRemoteRates(): void {
    this.rx_rate = 0
    this.tx_rate = 0
    this.rx_unit = 'B/s'
    this.tx_unit = 'B/s'
  }

  private async stopRuntime(): Promise<void> {
    if (!this.remoteMode) {
      AppManager.easytier.stop()
      return
    }
    if (this.stopping || !RemoteManageService.isCurrentSession(this.remoteSessionId)) {
      return
    }
    this.stopping = true
    try {
      const result = await RemoteManageService.stopConfig(this.uuid, this.remoteSessionId)
      if (result.ok) {
        sendToast('受控实例已停止', $r('sys.symbol.checkmark_circle'), 0)
        HMRouterMgr.pop()
      } else {
        sendToast('停止受控实例失败', $r('sys.symbol.exclamationmark_circle'), 1)
      }
    } catch (error) {
      sendToast(`停止失败：${(error as Error).message}`, $r('sys.symbol.exclamationmark_circle'), 1)
    } finally {
      this.stopping = false
    }
  }

  getRouteCost(cost: number): string {
    return cost === 1 ? 'P2P' : `Relay(${cost})`
  }

  @Builder
  RemotePeer(peer: PeerInfo) {
    Column() {
      Row({ space: 14 }) {
        // 左侧图标 + 名称
        Row({ space: 5 }) {
          Row() {
            SymbolGlyph($r("sys.symbol.superdevice"))
              .fontSize(Svp2fp(30 * 0.5))
              .fontColor([$r("sys.color.font_secondary")])
          }
          .alignItems(VerticalAlign.Center)
          .justifyContent(FlexAlign.Center)
          .width(30)
          .height(30)
          .borderRadius(8)
          .backgroundColor($r("sys.color.comp_background_tertiary"))

          Column() {
            Text(peer.hostname)
              .width('80%')
              .fontSize(14)
              .fontWeight(FontWeight.Bold)
              .textOverflow({
                overflow: TextOverflow.Ellipsis
              })
            Text(peer.ip+" / "+peer.peerId)
              .fontSize(11)
              .fontColor($r("sys.color.font_secondary"))
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
        }
        .layoutWeight(1)

        // 右侧延迟丢包
        if (peer.cost === 1) Column() {
          Text((Math.min(peer.latency_us / 1000, 999)).toFixed(0) + "ms")
            .fontSize(12)
            .fontWeight(FontWeight.Bold)
          Text("Loss " + Math.min(100, Math.max(0, peer.loss)).toFixed(1) + "%")
            .fontSize(10)
            .fontColor(peer.loss === 0 ? "#22c55e" : "#f87171")
        }
      }
      .width('100%')

      // 标签区
      Row({ space: 6 }) {
        Row() {
          Text(this.getRouteCost(peer.cost))
            .fontSize(10)
            .fontWeight(FontWeight.Bold)
            .padding({
              left: 6,
              right: 6,
              top: 3,
              bottom: 3
            })
            .borderRadius(4)
            .fontColor(peer.cost === 1 ? 'rgba(0,230,118,1)' : 'rgba(255,200,50,1)')
            .backgroundColor(peer.cost === 1 ? 'rgba(0,230,118,0.2)' : 'rgba(255,200,50,0.2)')
          ForEach(peer.protocol, (protocol: Protocol) => {
            Text(protocol.toString().toUpperCase())
              .fontSize(10)
              .fontWeight(FontWeight.Bold)
              .padding({
                left: 6,
                right: 6,
                top: 3,
                bottom: 3
              })
              .borderRadius(4)
              .fontColor(protocolColor(protocol))
              .backgroundColor(protocolBGColor(protocol))
              .margin({ left: 5 })
          })

          if (peer.resolvedRemoteAddr.length > 0) {
            Text(peer.resolvedRemoteAddr)
              .fontSize(10)
              .fontWeight(FontWeight.Bold)
              .padding({
                left: 6,
                right: 6,
                top: 3,
                bottom: 3
              })
              .borderRadius(4)
              .fontColor($r("sys.color.font_secondary"))
              .backgroundColor($r("sys.color.background_secondary"))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .margin({ left: 5 })
          }
        }

        Row({ space: 4 }) {
          SymbolGlyph($r("sys.symbol.arrow_up_and_down_square_portrait"))
            .fontSize(10)
            .fontColor([$r("sys.color.font_secondary")])
          Text(peer.getRate().toFixed(1) + peer.getRateUnit()).fontSize(10)
            .fontColor($r("sys.color.font_secondary"))
        }
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceBetween)
      .padding({ top: 10 })
    }
    .width('100%')
    .borderRadius(20)
    .padding(16)
    .backgroundColor($r("sys.color.comp_background_primary"))
  }

  @Builder
  content() {
    Scroll(this.scroller) {
      Column() {
        Column()
          .width('100%')
          .height(71)
        // 自身信息
        Column({ space: 20 }) {
          Row({ space: 6 }) {
            SymbolGlyph(this.runtimeHealthWarning ? $r("sys.symbol.exclamationmark_circle") :
              $r("sys.symbol.checkmark_circle"))
              .fontSize(14)
              .fontColor([this.runtimeHealthWarning ? '#f59e0b' : $r("sys.color.brand")])
            Text(this.runtimeHealthText)
              .fontSize(12)
              .fontColor(this.runtimeHealthWarning ? '#b45309' : $r("sys.color.font_secondary"))
              .maxLines(2)
              .layoutWeight(1)
          }
          .width('100%')
          .padding({ left: 10, right: 10, top: 7, bottom: 7 })
          .borderRadius(10)
          .backgroundColor(this.runtimeHealthWarning ? '#1Af59e0b' : $r("sys.color.comp_background_tertiary"))

          Row() {
            Column() {
              Row({ space: 8 }) {
                Text(this.remoteMode ? this.remoteDeviceName : (this.config?.hostname ?? "N/A"))
                  .fontSize(12)
                  .fontColor($r("sys.color.font_secondary"))
                  .fontWeight(FontWeight.Bold)
                SymbolGlyph($r("sys.symbol.plus_square_on_square"))
                  .fontSize(14)
                  .fontColor([$r("sys.color.font_secondary")])
              }

              Text(this.ip)
                .fontSize(28)
                .fontFamily("mono")
                .fontWeight(FontWeight.Bold)
                .fontColor($r("sys.color.font_primary"))
            }
            .alignItems(HorizontalAlign.Start)
            .justifyContent(FlexAlign.Center)
            .layoutWeight(1)

            Column({ space: 4 }) {
              DiscoverBall({ yellow: this.ip === "waiting" })
            }
          }

          Row() {
            Row({ space: 4 }) {
              SymbolGlyph($r("sys.symbol.pc_ic_tab_index_1"))
                .fontColor([$r("sys.color.brand")])
                .fontSize(14)

              Row({ space: 4 }) {
                Text("NAT")
                  .fontSize(12)

                Row({ space: 4 }) {
                  Text(`UDP ${natTypeToText(this.udp_nat)}`)
                    .fontSize(12)

                  Divider()
                    .vertical(true)
                    .strokeWidth(2)
                    .color($r("sys.color.comp_divider"))
                    .lineCap(LineCapStyle.Round)
                    .height(Sfp2vp(12) * 0.7)

                  Text(`TCP ${natTypeToText(this.tcp_nat)}`)
                    .fontSize(12)
                }
              }
              .justifyContent(FlexAlign.Start)
            }
            .padding({
              top: 5,
              bottom: 5,
              left: 5,
              right: 10
            })
            .borderRadius(20)
            .borderColor($r("sys.color.interactive_hover"))
            .backgroundColor($r("sys.color.comp_background_tertiary"))
            .borderWidth(2)

            Divider()
              .strokeWidth(2)
              .lineCap(LineCapStyle.Round)
              .color(Color.Transparent)
              .layoutWeight(100)
              .margin({ left: 10 })
              .linearGradient({
                direction: GradientDirection.Right,
                colors: [[$r("sys.color.comp_divider"), 0], [$r("sys.color.comp_background_primary"), 1]]
              })
          }
          .width('100%')

          Column({ space: 6 }) {
            Row() {
              Row({ space: 4 }) {
                SymbolGlyph($r("sys.symbol.arrow_up"))
                  .fontColor([$r("sys.color.font_secondary")])
                Text("上传")
                  .fontColor($r("sys.color.font_secondary"))
              }

              Row({ space: 4 }) {
                SymbolGlyph($r("sys.symbol.arrow_down"))
                  .fontColor([$r("sys.color.font_secondary")])
                Text("下载")
                  .fontColor($r("sys.color.font_secondary"))
              }
            }
            .width('100%')
            .justifyContent(FlexAlign.SpaceBetween)

            Row() {
              Row({ space: 2 }) {
                Text(this.tx_rate.toFixed(1))
                  .fontSize(20)
                Text(this.tx_unit)
                  .fontSize(10)
                  .fontColor($r("sys.color.font_secondary"))
              }
              .alignItems(VerticalAlign.Bottom)

              Row({ space: 2 }) {
                Text(this.rx_rate.toFixed(1))
                  .fontSize(20)
                Text(this.rx_unit)
                  .fontSize(10)
                  .fontColor($r("sys.color.font_secondary"))
              }
              .alignItems(VerticalAlign.Bottom)
            }
            .width('100%')
            .justifyContent(FlexAlign.SpaceBetween)
          }
          .width('100%')
          .justifyContent(FlexAlign.Center)
        }
        .padding(20)
        .borderRadius(20)
        .backgroundColor($r("sys.color.comp_background_primary"))

        WaterFlow() {
          if (this.instanceInfo != undefined) {
            LazyForEach(this.instanceInfo!, (peer: PeerInfo) => {
              this.RemotePeer(peer)
            })
          }
        }
        .columnsGap(10)
        .rowsGap(10)
        .columnsTemplate("1fr".repeat(Math.max(1, WindowUtil.uiType - 1)))
        .width('100%')
        .margin({ top: 10 })
      }
    }
    .padding({ left: 15, right: 15 })
    .width("100%")
    .height('100%')
    .backgroundColor($r("sys.color.background_secondary"))
    .align(Alignment.Top)
    .scrollBar(BarState.Off)
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
    .bindToScrollable([this.scroller])
    .titleBar({
      style: this.navTitleStyle(),
      content: {
        title: {
          mainTitle: this.name,
          subTitle: this.remoteMode ? this.remoteDeviceName : this.uuid
        },
        menu: {
          value: [
            HdsMenuButton(this.stopping ? "停止中" : "停止运行", $r("sys.symbol.pause_fill"), () => {
              void this.stopRuntime()
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
  }

  immersiveCallback = (sharableTarget: harmonyShare.SharableTarget) => {
    if (this.config) {
      buildShareData(this.config, (data) => {
        sharableTarget.share(data);
      }, false, this.name, this.uuid)
    }
  }
}
