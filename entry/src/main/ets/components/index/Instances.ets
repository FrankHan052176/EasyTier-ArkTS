import Manager from "../../Manager"
import { Config } from "../../util/ETConfig"
import { CompTitle } from "./Basic"
import { LengthMetrics } from "@kit.ArkUI"

@Extend(List)
function comp_list() {
  .onTouch((event) => event.stopPropagation())
  .maintainVisibleContentPosition(true)
  .alignListItem(ListItemAlign.Center)
  .width('100%')
  .scrollBar(BarState.Off)
  .fadingEdge(true, { fadingEdgeLength: LengthMetrics.vp(20) })
  .chainAnimation(true)
  .scrollSnapAlign(ScrollSnapAlign.START)
  .animation({
    duration: 200,
    curve: Curve.EaseIn
  })
}

@Extend(Column)
function comp_bg() {
  .borderRadius(18)
  .width('100%')
  .height('100%')
  .backgroundColor($r("sys.color.comp_background_primary"))
  .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
}

@ComponentV2
export struct Instances {
  build() {
    Column() {
      CompTitle("实例", 'rgba(0,230,118,1)', ()=>{return Manager.configs.size})
      List({space: 8}) {
        ForEach(Array.from(Manager.configs.values()), (config: Config, index: number) => {
          ListItem() {
          }
          .width('100%')
        })
      }
      .comp_list()
    }
    .comp_bg()
    .geometryTransition("instances")
  }
}