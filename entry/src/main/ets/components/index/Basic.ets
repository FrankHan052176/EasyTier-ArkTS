import { Sfp2vp } from '../../AppManager'

@Builder
export function CompTitle(title: string, color: ResourceColor, sizeFunc: () => number,
  ge: Resource = $r("app.string.i18_ge"), backFunc: (() => void) | undefined = undefined) {
  Row() {
    Row() {
      if (backFunc !== undefined) {
        SymbolGlyph($r("sys.symbol.chevron_left"))
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor([color])
          .onClick(() => {
            backFunc()
          })
      } else {
        Divider()
          .vertical(true)
          .color(color)
          .strokeWidth(5)
          .lineCap(LineCapStyle.Round)
          .height('70%')
      }
      Text(title)
        .fontSize(22)
        .fontColor($r("sys.color.font_primary"))
        .margin({ left: 5 })
        .layoutWeight(100)
        .textOverflow({
          overflow: TextOverflow.Ellipsis
        })
    }.layoutWeight(100)
    .height('100%')

    Row() {
      if (sizeFunc() >= 0) {
        Text($r("app.string.i18_total")).fontSize(10).fontColor($r("sys.color.font_primary"))
        Text("" + sizeFunc()).fontSize(20).fontColor($r("sys.color.font_primary"))
        Text(ge).fontSize(10).fontColor($r("sys.color.font_primary"))
      }
    }
    .height('100%')
    .alignItems(VerticalAlign.Bottom)
    .justifyContent(FlexAlign.End)
  }
  .height(Sfp2vp(22))
  .justifyContent(FlexAlign.SpaceBetween)
  .padding({ left: 10, right: 10 })
  .margin({ top: 15, bottom: 5 })
  .width('100%')
}