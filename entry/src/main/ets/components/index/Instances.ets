import { CompTitle } from "./Basic"
import { LengthMetrics } from "@kit.ArkUI"
import { AppManager } from "../../AppManager"
import { HMRouterMgr } from "@hadss/hmrouter"
import { HMRouterTransitions } from "@hadss/hmrouter-transitions"

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

  @Computed
  get CompSize() {
    return AppManager.layout.getCompSize("Instances")
  }

  @Computed
  get ItemHeight() {
    return (this.list_height-(this.CompSize.lane_h == 2?6:2))/(this.CompSize.lane_h == 2?6.5:2.5)
  }

  @Computed
  get EmptyHeight() {
    return this.list_height-this.ItemHeight-3
  }

  build() {
    Column() {
      CompTitle("实例", $r("sys.color.brand"), ()=>{return AppManager.data.configUUIDMap.size})
      Column() {
        List({space: 2}) {
          ForEach(Array.from(AppManager.data.configUUIDNameMap.keys()), (uuid: string, index) => {
            ListItem() {
              Column() {
                Text(AppManager.data.configUUIDNameMap.get(uuid)!)
                  .maxLines(1)
                  .fontWeight(index===this.selected?FontWeight.Bold:FontWeight.Normal)
                  .textOverflow({
                    overflow: TextOverflow.Ellipsis
                  })
                Text(uuid)
                  .fontSize(12)
                  .fontColor($r("sys.color.font_secondary"))
                  .maxLines(1)
                  .textOverflow({
                    overflow: TextOverflow.Ellipsis
                  })
              }
              .alignItems(HorizontalAlign.Start)
              .opacity(index===this.selected?1:0.5)
              .height(this.ItemHeight)
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
            .id("home_"+uuid)
            .gesture(
              TapGesture({ count: 2 })
                .onAction(() => {
                  const animator = HMRouterTransitions.cardLongTake("home_"+uuid, "edit_content", {
                    onTransitionStart: () => {}, onTransitionEnd: () => {}
                  });
                  HMRouterMgr.push({ pageUrl: 'EditPage', param: uuid, animator: animator });
                })
            )
          })
          ListItem().height(this.EmptyHeight)
        }
        .width('100%')
        .height('100%')
        .friction(0.8)
        .edgeEffect(EdgeEffect.None)
        .scrollBar(BarState.Off)
        .scrollSnapAlign(ScrollSnapAlign.START)
        .onAreaChange((_a,b) => {
          this.list_height = (b.height.valueOf() as number)
        })
        .onScrollIndex((start, end, center) => {
          this.selected = start
          if (AppManager.data.configUUIDNameMap.size == 0) {
            AppManager.easytier.selected = undefined
          }else {
            AppManager.easytier.selected = Array.from(AppManager.data.configUUIDNameMap.keys())[this.selected]
          }
        })
        .fadingEdge(true, { fadingEdgeLength: LengthMetrics.vp(3) })
      }
      .padding({top: 5, left: 10, right: 10, bottom: 10})
      .width('100%')
      .layoutWeight(100)
    }
    .comp_bg()
  }
}