import { Config } from "../../util/ETConfig";
import { EventRow } from "../content/EventRow";
import { RemotePeers } from "../content/RemotePeers";
import { UIType, WindowUtil } from "../../WindowUtil";
import { EventHelper } from "../../util/EventHelper";
import { MyNodeInfo, NetworkInstanceRunningInfo } from "../../protobuf/api_manage";
import { PeerRoutePair } from "../../protobuf/api_instance";

@ComponentV2
export struct InstanceStatus {
  @Param @Require config: Config
  @Local events: string[] = []
  @Local pairs: Map<number, PeerRoutePair> = new Map
  @Local myInfo: MyNodeInfo | undefined

  aboutToAppear(): void {
    EventHelper.emitterListener("updateInfo_"+this.config.instance_id, (data) => {
      let info: NetworkInstanceRunningInfo = data.data!.info
      if (info.events.length > this.events.length) {
        this.events.push(...info.events.slice(this.events.length))
      }
      let pairs = info.peerRoutePairs
      let nowIds = new Set<number>()
      for (const pair of pairs) {
        nowIds.add(pair.route!.peerId)
        this.pairs.set(pair.route!.peerId, pair)
      }
      for (const id of Array.from(this.pairs.keys())) {
        if (!nowIds.has(id)) {
          this.pairs.delete(id)
        }
      }
      this.myInfo = info.myNodeInfo
    })
  }

  build() {
    Scroll() {
      Column() {
        Text("对端")
          .fontSize(12)
          .fontColor($r("sys.color.font_secondary"))
          .margin({left: 10, bottom: 5})
        RemotePeers({pairs: this.pairs, myInfo: this.myInfo, comp_width: (WindowUtil.width-20)*(WindowUtil.uiType == UIType.Column_3?0.8:1)})
          .margin({bottom: 10})
        Text("事件")
          .fontSize(12)
          .fontColor($r("sys.color.font_secondary"))
          .margin({left: 10, bottom: 5})
        Column() {
          List({space: 5}) {
            ListItem() {}
            .height(10)
            .width('100%')
            ForEach(this.events, (event: string) => {
              EventRow({rawEvent: event})
            })
            ListItem() {}
            .height(10)
            .width('100%')
          }
          .maintainVisibleContentPosition(true)
          .scrollBar(BarState.Off)
          .width('100%')
          .height('100%')
        }
        .padding({left: 10, right: 10})
        .borderRadius(18)
        .backgroundColor($r("sys.color.comp_background_primary"))
        .width("100%")
        .height(WindowUtil.height*0.5)
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.START, SafeAreaEdge.BOTTOM])
        .margin({bottom: 10})
        Blank()
          .height(WindowUtil.height*0.1)
          .width('100%')
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.START, SafeAreaEdge.BOTTOM])
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.START, SafeAreaEdge.BOTTOM])
    }
    .scrollBar(BarState.Off)
    .width('100%')
    .height(WindowUtil.height-121)
    .align(Alignment.Top)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.START, SafeAreaEdge.BOTTOM])
    .edgeEffect(EdgeEffect.Spring)
  }
}