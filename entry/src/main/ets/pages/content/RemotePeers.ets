import Manager from "../../Manager"
import { Config} from "../../util/config/ETConfig"
import { PeerRoutePair } from "../../util/info/PeerInfo"
import { ItemBuilder } from "../../util/ItemBuilders"

@ComponentV2
export struct RemotePeers {
  @Param @Require config: Config
  @Param @Require comp_width: number
  @Local item_width: number = 160
  @Local item_height: number = 80

  @Computed
  get info() {
    return Manager.info!
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
          ItemBuilder({
            isSelected: value.route.peer_id == undefined,
            item: value,
            itemWidth: this.item_width,
            switchHighlight: false
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