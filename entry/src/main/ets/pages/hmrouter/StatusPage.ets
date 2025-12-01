import { HMRouter, HMRouterMgr } from '@hadss/hmrouter'
import { deviceInfo } from '@kit.BasicServicesKit'
import { HdsNavigation, HdsNavigationTitleMode, ScrollEffectType, HdsNavigationAttribute } from '@kit.UIDesignKit'
import { LengthMetrics } from '@kit.ArkUI'
import { AppManager, Sfp2vp, Svp2fp } from '../../AppManager'
import { HdsMenuButton, MenuButton } from '../Components'
import { NetworkConfig } from '../../protobuf/api_manage'
import { EventHelper } from '../../util/EventHelper'
import { convertAddrToIp } from '../../util/Conversion'
import { DiscoverBall } from '../../components/status/DiscoverBall'
import { NatType, natTypeToJSON } from '../../protobuf/common'
import { PeerInfo } from '../../class/InstanceInfo'
import { Protocol, protocolBGColor, protocolColor } from '../../util/ETConfig'
import { WindowUtil } from '../../WindowUtil'

@HMRouter({ pageUrl: "StatusPage" })
@ComponentV2
export struct StatusPage {
  @Local uuid: string = ""
  @Local name: string = ""
  @Local config: NetworkConfig | null = null;
  scroller: Scroller = new Scroller();
  @Local ip: string = ""
  @Local tcp_nat: NatType = NatType.Unknown
  @Local udp_nat: NatType = NatType.Unknown
  @Local rx_rate: number = 0
  @Local tx_rate: number = 0
  @Local rx_unit: string = "B/s"
  @Local tx_unit: string = "B/s"

  aboutToAppear(): void {
    this.uuid = HMRouterMgr.getCurrentParam() as string;
    this.name = AppManager.data.configUUIDNameMap.get(this.uuid)!
    this.config = AppManager.data.configUUIDMap.get(this.uuid)!
    this.ip = this.config.dhcp?"waiting":this.config.virtual_ipv4!
    EventHelper.emitterListener("updateInfo_"+this.uuid, () => {
      let info = AppManager.easytier.runningNetworks.get(this.uuid)
      if (info) {
        if (info.my_node_info?.virtual_ipv4?.address) {
          // 获取IP
          let convertedIp = convertAddrToIp(info.my_node_info?.virtual_ipv4?.address.addr)
          if (this.ip !== convertedIp) {
            this.ip = convertedIp
          }
        }else {
          this.ip = "waiting"
        }

        this.udp_nat = info.my_node_info?.stun_info?.udp_nat_type ?? NatType.Unknown
        this.tcp_nat = info.my_node_info?.stun_info?.tcp_nat_type ?? NatType.Unknown
      }
    })
    setInterval(() => {
      let instanceInfo = AppManager.easytier.instanceInfos.get(this.uuid)
      if (instanceInfo) {
        if (instanceInfo.getDownloadRate() >= 0) {
          this.rx_rate = instanceInfo.getDownloadRate()
          this.rx_unit = instanceInfo.getDownloadRateUnit()
        }
        if (instanceInfo.getUploadRate() >= 0) {
          this.tx_rate = instanceInfo.getUploadRate()
          this.tx_unit = instanceInfo.getUploadRateUnit()
        }
      }
    }, 1000)
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
          Row(){
            SymbolGlyph($r("sys.symbol.superdevice"))
              .fontSize(Svp2fp(30*0.5))
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
              .fontSize(14)
              .fontWeight(FontWeight.Bold)
            Text(peer.ip)
              .fontSize(11)
              .fontColor($r("sys.color.font_secondary"))
          }
          .alignItems(HorizontalAlign.Start)
        }
        .layoutWeight(1)

        // 右侧延迟丢包
        if(peer.cost === 1) Column() {
          Text((peer.latency_us/1000).toFixed(0)+"ms")
            .fontSize(12)
            .fontWeight(FontWeight.Bold)
          Text("Loss " + peer.loss.toFixed(1)+"%")
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
            .padding({ left: 6, right: 6, top: 3, bottom: 3 })
            .borderRadius(4)
            .fontColor(peer.cost===1?'rgba(0,230,118,1)':'rgba(255,200,50,1)')
            .backgroundColor(peer.cost===1?'rgba(0,230,118,0.2)':'rgba(255,200,50,0.2)')
          ForEach(peer.protocol, (protocol: Protocol) => {
            Text(protocol.toString().toUpperCase())
              .fontSize(10)
              .fontWeight(FontWeight.Bold)
              .padding({ left: 6, right: 6, top: 3, bottom: 3 })
              .borderRadius(4)
              .fontColor(protocolColor(protocol))
              .backgroundColor(protocolBGColor(protocol))
              .margin({left: 5})
          })
        }

        Row({ space: 4 }) {
          SymbolGlyph($r("sys.symbol.arrow_up_and_down_square_portrait"))
            .fontSize(10)
            .fontColor([$r("sys.color.font_secondary")])
          Text(peer.getRate().toFixed(1)+peer.getRateUnit()).fontSize(10)
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
        if (deviceInfo.sdkApiVersion >= 20) {
          Column()
            .width('100%')
            .height(71)
        }
        // 自身信息
        Column({ space: 20 }) {
          Row() {
            Column() {
              Row({ space: 8 }) {
                Text(this.config!.hostname)
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
              DiscoverBall({yellow: this.ip === "waiting"})
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

                Row({space: 4}) {
                  Text(natTypeToJSON(this.udp_nat))
                    .fontSize(12)

                  Divider()
                    .vertical(true)
                    .strokeWidth(2)
                    .color($r("sys.color.comp_divider"))
                    .lineCap(LineCapStyle.Round)
                    .height(Sfp2vp(12)*0.7)

                  Text(natTypeToJSON(this.tcp_nat))
                    .fontSize(12)
                }
              }
              .justifyContent(FlexAlign.Start)
            }
            .padding({top: 5, bottom: 5, left: 5, right: 10})
            .borderRadius(20)
            .borderColor($r("sys.color.interactive_hover"))
            .backgroundColor($r("sys.color.comp_background_tertiary"))
            .borderWidth(2)

            Divider()
              .strokeWidth(2)
              .lineCap(LineCapStyle.Round)
              .color(Color.Transparent)
              .layoutWeight(100)
              .margin({left: 10})
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
                Text(this.rx_rate.toFixed(1))
                  .fontSize(20)
                Text(this.rx_unit)
                  .fontSize(10)
                  .fontColor($r("sys.color.font_secondary"))
              }
              .alignItems(VerticalAlign.Bottom)
              Row({ space: 2 }) {
                Text(this.tx_rate.toFixed(1))
                  .fontSize(20)
                Text(this.tx_unit)
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
          LazyForEach(AppManager.easytier.instanceInfos.get(this.uuid)!.peers, (peer: PeerInfo) => {
            this.RemotePeer(peer)
          })
        }
        .columnsGap(10)
        .rowsGap(10)
        .columnsTemplate("1fr".repeat(Math.max(1,WindowUtil.uiType-1)))
        .width('100%')
        .margin({top: 10})
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

  build() {
    Column() {
      if (deviceInfo.sdkApiVersion >= 20) {
        HdsNavigation() {
          this.content()
        }
        .bindToScrollable([this.scroller])
        .titleBar({
          style: {
            scrollEffectOpts: {
              enableScrollEffect: true,
              scrollEffectType: ScrollEffectType.GRADUAL_BLUR,
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
                  backgroundColor: $r("sys.color.interactive_hover")
                },
                backIconStyle: {
                  backgroundColor: $r("sys.color.interactive_hover"),
                  iconColor: $r("sys.color.font_primary")
                }
              }
            }
          },
          content: {
            title: {
              mainTitle: this.name,
              subTitle: this.uuid
            },
            menu: {
              value: [
                HdsMenuButton("stop", $r("sys.symbol.pause_fill"), () => {
                  AppManager.easytier.stop()
                  HMRouterMgr.pop()
                })
              ]
            }
          }
        })
        .mode(NavigationMode.Stack)
        .titleMode(HdsNavigationTitleMode.MINI)
        .hideBackButton(false)
        .hideTitleBar(false)
      }else {
        Navigation() {
          this.content()
        }
        .mode(NavigationMode.Stack)
        .titleMode(NavigationTitleMode.Mini)
        .title({
          main: this.name!,
          sub: this.uuid!
        }, {
          backgroundColor: $r('sys.color.background_secondary')
        })
        .hideBackButton(false)
        .menus([
          MenuButton("stop", $r("sys.symbol.pause_fill"), () => {
            AppManager.easytier.stop()
            HMRouterMgr.pop()
          }),
        ])
      }
    }
    .backgroundColor($r('sys.color.background_secondary'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}