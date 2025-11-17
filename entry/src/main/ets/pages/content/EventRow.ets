import { unwrappedRawEvent } from "../../util/Conversion"
import { Event } from "../../util/info/PeerInfo"

@ComponentV2
export struct EventRow {
  @Param @Require rawEvent: string
  @Local event: Event = unwrappedRawEvent(this.rawEvent)

  build() {
    Column() {
      Row() {
        Text(this.event.time)
          .fontSize(12)
          .fontColor($r("sys.color.font_secondary"))
        Text($r("app.string.event_"+this.event.type))
          .fontSize(12)
          .fontColor($r("sys.color.font_secondary"))
          .margin({left: 5})
      }
      .alignItems(VerticalAlign.Center)
      .justifyContent(FlexAlign.Start)
      .width('100%')
      Text(this.event.msg)
        .fontSize(13)
        .width('100%')
    }
    .alignItems(HorizontalAlign.Start)
    .justifyContent(FlexAlign.Start)
    .width('100%')
  }
}