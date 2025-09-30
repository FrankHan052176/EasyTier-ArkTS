import Manager from "../Manager";
import { Config } from "../util/config/ETConfig";
import { EventRow } from "./content/EventRow";
import { LengthUnit } from "@kit.ArkUI";
import { Event } from "../util/info/PeerInfo";
import { RemotePeers } from "./content/RemotePeers";

@ComponentV2
export struct InstanceStatus {
  @Param @Require config: Config

  build() {
    Scroll() {
      Column() {
        Text("对端")
          .fontSize(12)
          .fontColor($r("sys.color.font_secondary"))
          .margin({left: 10, bottom: 5, top: 66})
        RemotePeers({config: this.config, comp_width: Manager.width-20})
          .margin({bottom: 10})
        Text("事件")
          .fontSize(12)
          .fontColor($r("sys.color.font_secondary"))
          .margin({left: 10, bottom: 5})
        Column() {
          List() {
            ForEach(Manager.infos.get(this.config.instance_id)!.events, (event: Event) => {
              EventRow({event: event})
            })
          }
          .scrollBar(BarState.Off)
          .width('100%')
          .height('100%')
        }
        .padding(10)
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