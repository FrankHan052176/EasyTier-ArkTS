import { CompTitle } from "./Basic"
import { LengthMetrics } from "@kit.ArkUI"
import { AppManager } from "../../AppManager"
import { HMRouterMgr } from "@hadss/hmrouter"

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
  @Local selected: number = 0;
  @Local list_height: number = 0

  build() {
    Column() {
      CompTitle("实例", $r("sys.color.brand"), ()=>{return AppManager.data.configUUIDMap.size})
      Column() {
        List({space: 2}) {
          ForEach(Array.from(AppManager.data.configNameUUIDMap.keys()), (name: string, index) => {
            ListItem() {
              Column() {
                Text(name)
                  .maxLines(1)
                  .fontWeight(index===this.selected?FontWeight.Bold:FontWeight.Normal)
                  .textOverflow({
                    overflow: TextOverflow.Ellipsis
                  })
                Text(AppManager.data.configNameUUIDMap.get(name)!)
                  .fontSize(12)
                  .fontColor($r("sys.color.font_secondary"))
                  .maxLines(1)
                  .textOverflow({
                    overflow: TextOverflow.Ellipsis
                  })
              }
              .alignItems(HorizontalAlign.Start)
              .opacity(index===this.selected?1:0.5)
              .height((this.list_height-4)/2.5)
              .animation({
                duration: 300,
                curve: Curve.Ease
              })
            }
            .padding({left: index===this.selected?5:10, right: index===this.selected?5:10})
            .animation({
              duration: 300,
              curve: Curve.Ease
            })
            .gesture(
              TapGesture({ count: 2 })
                .onAction(() => {
                  HMRouterMgr.push({ pageUrl: 'EditPage', param: name });
                })
            )
          })
        }
        .width('100%')
        .height('100%')
        .friction(0.8)
        .edgeEffect(EdgeEffect.None)
        .scrollBar(BarState.Off)
        .scrollSnapAlign(ScrollSnapAlign.CENTER)
        .onAreaChange((_a,b) => {
          this.list_height = (b.height.valueOf() as number)-20
        })
        .onScrollIndex((_start, _end, center) => {
          this.selected = center
        })
        .fadingEdge(true, { fadingEdgeLength: LengthMetrics.vp(5) })
      }
      .padding({top: 5, left: 10, right: 10, bottom: 10})
      .width('100%')
      .layoutWeight(100)
    }
    .comp_bg()
  }
}