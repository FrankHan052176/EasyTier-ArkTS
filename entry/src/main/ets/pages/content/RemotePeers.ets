import Manager from "../../Manager"
import { Config, peer, Protocol, protocolColor } from "../../util/config/ETConfig"
import { FancyItem } from "../Components"
import { LengthMetrics } from "@kit.ArkUI"
import { NetworkInstanceRunningInfo, PeerInfo, PeerRoutePair } from "../../util/info/PeerInfo"
import Logger from "../../util/Logger"
import { convertAddrToIp } from "../../util/Conversion"

let protocols = [Protocol.TCP, Protocol.UDP, Protocol.QUIC, Protocol.WS, Protocol.WSS, Protocol.WG]

@ComponentV2
export struct RemotePeers {
  @Param @Require config: Config
  @Param @Require comp_width: number
  @Local item_width: number = 160
  @Local item_height: number = 80
  @Local edit: peer = new peer()
  @Local add: peer = new peer()
  @Local old: peer = new peer()

  @Computed
  get info() {
    return Manager.infos.get(this.config.instance_id)!
  }

  @Computed
  get full_infos() {
    if (this.info) {
      return [
        {
          route: {
            ipv4_addr: this.info.my_node_info.virtual_ipv4,
            hostname: this.info.my_node_info.hostname,
            version: this.info.my_node_info.version
          }
        } as PeerRoutePair,
        ...this.info.peer_route_pairs
      ]
    }else {
      return []
    }
  }

  @Computed
  get list_lanes() {
    return Math.min(Math.floor(this.comp_width/this.item_width), 5);
  }

  getProtocol(value: PeerRoutePair): Protocol[] {
    let arr = new Array<Protocol>()
    if (value.peer) {
      value.peer.conns.forEach((conn) => {
        if (conn.tunnel) {
          arr.push(conn.tunnel.tunnel_type as Protocol)
        }
      })
    }
    return arr
  }

  getRouteCost(value: PeerRoutePair): string {
    if (value.route) {
      const cost = value.route.cost
      return cost ? cost === 1 ? 'p2p' : `relay(${cost})` : "local"
    }else {
      return "?"
    }
  }

  @Builder
  peerContent(value: PeerRoutePair) {
    Stack({alignContent: Alignment.TopStart}) {
      Row() {
        ForEach(this.getProtocol(value), (item: Protocol) => {
          Text(item.toUpperCase())
            .fontColor($r("sys.color.font_on_primary"))
            .fontSize(12)
            .borderRadius(6)
            .backgroundColor(protocolColor(item))
            .padding({top: 3, bottom: 3, right: 5, left: 5})
            .textAlign(TextAlign.Center)
        })
      }
      .alignItems(VerticalAlign.Center)
      .justifyContent(FlexAlign.End)
      .width('100%')
      .margin({bottom: 10})
      .offset({
        x: -3,
        y: 3
      })
      Row() {
        Text(this.getRouteCost(value))
          .fontColor($r("sys.color.font_on_primary"))
          .fontSize(12)
          .borderRadius(6)
          .backgroundColor($r("sys.color.comp_background_emphasize"))
          .padding({top: 3, bottom: 3, right: 5, left: 5})
          .textAlign(TextAlign.Center)
      }
      .alignItems(VerticalAlign.Center)
      .justifyContent(FlexAlign.Start)
      .width('100%')
      .margin({bottom: 10})
      .offset({
        x: 3,
        y: 3
      })
      Column() {
        Text(value.route.hostname)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .fontSize(14)
          .fontColor($r("sys.color.font_primary"))
          .textAlign(TextAlign.Center)
          .padding({left: 10, right: 10})
        Text(value.route.ipv4_addr?convertAddrToIp(value.route.ipv4_addr?.address.addr):"")
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .fontSize(14)
          .fontColor($r("sys.color.font_primary"))
          .textAlign(TextAlign.Center)
          .padding({left: 10, right: 10})
      }
      .height('100%')
      .width('100%')
      .alignItems(HorizontalAlign.Center)
      .justifyContent(FlexAlign.Center)
    }
  }

  build() {
    Column() {
      Row() {
        Text("Peers")
          .textAlign(TextAlign.Start)
          .fontSize(18)
          .margin({left: 5})
          .fontColor($r("sys.color.font_primary"))
      }
      .width('100%')
      .margin({left: 5, bottom: 5})
      List({space: 10, initialIndex: 0}) {
        ForEach(this.full_infos, (value:PeerRoutePair) => {
          FancyItem({
            item_width: this.item_width,
            item_height: this.item_height,
            needCheckbox: false,
            needMenu: false,
            contentBuilder: () => {
              this.peerContent(value)
            },
            sheetBuilder: () => {},
            clickCallback: () => {

            }
          })
            .onAppear(() => {
              Manager.infos.get(this.config.instance_id)!.peer_route_pairs.forEach((value) => {
                Logger.debug("peer_route_pairs:"+JSON.stringify(value))
              })
            })
        })
      }
      .borderRadius(10)
      .maintainVisibleContentPosition(true)
      .scrollBar(BarState.Off)
      .lanes(this.list_lanes, 10)
      .listDirection(Axis.Vertical)
      .width((this.list_lanes-1)*(this.item_width+10)+this.item_width)
      .height(this.full_infos.length>this.list_lanes?this.item_height*1.6+10:this.item_height)
    }
    .width(this.comp_width)
    .alignItems(HorizontalAlign.Start)
    .borderRadius(18)
    .backgroundColor($r("sys.color.comp_background_primary"))
    .padding(10)
    .clip(true)
  }
}