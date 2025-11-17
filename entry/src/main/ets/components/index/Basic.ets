import { Sfp2vp } from "../../ContextUtil"
import { LengthMetrics } from "@kit.ArkUI"

@Builder
export function CompTitle(title: string, color: ResourceColor, sizeFunc: () => number, ge: Resource = $r("app.string.i18_ge"), needCnt: boolean = true) {
  Row() {
    Row() {
      Divider().vertical(true).color(color).strokeWidth(5).lineCap(LineCapStyle.Round).height('70%')
      Text(title).fontSize(22).fontColor($r("sys.color.font_primary")).margin({left: 5})
    }
    Row() {
      if (needCnt) {
        Text($r("app.string.i18_total")).fontSize(10).fontColor($r("sys.color.font_primary"))
        Text(""+sizeFunc()).fontSize(20).fontColor($r("sys.color.font_primary"))
        Text(ge).fontSize(10).fontColor($r("sys.color.font_primary"))
      }
    }
    .height('100%')
    .alignItems(VerticalAlign.Bottom)
  }
  .height(Sfp2vp(22))
  .justifyContent(FlexAlign.SpaceBetween)
  .padding({left: 10, right: 15})
  .margin({top: 15, bottom: 5})
  .width('100%')
}

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