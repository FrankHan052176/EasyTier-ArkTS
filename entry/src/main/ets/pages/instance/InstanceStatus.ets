import Manager, { UIType } from "../../Manager";
import { Config } from "../../util/config/ETConfig";
import { EventRow } from "../content/EventRow";
import { LengthUnit } from "@kit.ArkUI";
import { Event } from "../../util/info/PeerInfo";
import { RemotePeers } from "../content/RemotePeers";

@ComponentV2
export struct InstanceStatus {
  @Param @Require config: Config

  build() {
    Scroll() {
      Column() {
        Text("对端")
          .fontSize(12)
          .fontColor($r("sys.color.font_secondary"))
          .margin({left: 10, bottom: 5})
        RemotePeers({config: this.config, comp_width: (Manager.width-20)*(Manager.uiType == UIType.Column_3?0.8:1)})
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
            ForEach(Manager.info?Manager.info.events:[], (event: Event) => {
              EventRow({event: event})
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
        .height(Manager.height*0.5)
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.START, SafeAreaEdge.BOTTOM])
        .margin({bottom: 10})
        Blank()
          .height(Manager.height*0.1)
          .width('100%')
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.START, SafeAreaEdge.BOTTOM])
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.START, SafeAreaEdge.BOTTOM])
    }
    .scrollBar(BarState.Off)
    .width('100%')
    .height(Manager.height-121)
    .align(Alignment.Top)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.START, SafeAreaEdge.BOTTOM])
    .edgeEffect(EdgeEffect.Spring)
  }
}