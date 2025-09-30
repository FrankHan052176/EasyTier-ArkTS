import {Event} from '../../util/info/PeerInfo'

@ComponentV2
export struct EventRow {
  @Param @Require event: Event

  build() {
    Column() {
      Text(this.event.time+"|"+this.event.type)
        .fontSize(12)
        .fontColor($r("sys.color.font_secondary"))
        .margin({left: 5})
      Text(this.event.msg)
        .width('100%')
    }
    .alignItems(HorizontalAlign.Start)
    .justifyContent(FlexAlign.Start)
    .width('100%')
    .margin({bottom: 5})
  }
}