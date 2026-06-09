import { protocolBGColor, protocolColor, Protocol } from '../../util/Conversion';
import { Svp2fp } from '../../AppManager';

export interface ListFieldItemModel {
  key: string
  index: number
  type: string
  rawText: string
  title: string
  subtitle: string
  protocol: Protocol | undefined
  valid: boolean
}

@Builder
function listItemIcon(type: string) {
  Row() {
    if (type === "route") {
      SymbolGlyph($r("sys.symbol.arrow_triangle_divide"))
        .fontSize(Svp2fp(24))
        .fontColor([$r("sys.color.font_secondary")])
    } else if (type === "peer") {
      SymbolGlyph($r("sys.symbol.worldclock"))
        .fontSize(Svp2fp(24))
        .fontColor([$r("sys.color.font_secondary")])
    } else if (type === "listener" || type === "mapped_listener") {
      SymbolGlyph($r("sys.symbol.dot_radiowaves_left_and_right"))
        .fontSize(Svp2fp(24))
        .fontColor([$r("sys.color.font_secondary")])
    } else if (type === "port_forward") {
      SymbolGlyph($r("sys.symbol.arrow_bounce_right"))
        .fontSize(Svp2fp(24))
        .fontColor([$r("sys.color.font_secondary")])
    } else {
      SymbolGlyph($r("sys.symbol.arrow_triangle_merge"))
        .fontSize(Svp2fp(24))
        .fontColor([$r("sys.color.font_secondary")])
    }
  }
  .backgroundColor($r("sys.color.comp_background_tertiary"))
  .padding(10)
  .borderRadius(8)
  .alignItems(VerticalAlign.Center)
  .justifyContent(FlexAlign.Center)
}

@Builder
function protocolPill(protocol: Protocol | undefined) {
  if (protocol !== undefined) {
    Text(protocol.toString().toUpperCase())
      .fontSize(11)
      .fontColor(protocolColor(protocol))
      .fontWeight(FontWeight.Bold)
      .borderRadius(6)
      .padding({
        top: 4,
        bottom: 4,
        left: 6,
        right: 6
      })
      .backgroundColor(protocolBGColor(protocol))
  }
}

@ComponentV2
export struct ListFieldValue {
  @Param @Require item: ListFieldItemModel;

  @Styles
  backgroundStyle() {
    .width('100%')
    .borderRadius(18)
    .padding({
      left: 12,
      right: 12,
      top: 13,
      bottom: 13
    })
    .backgroundColor($r("sys.color.comp_background_primary"))
  }

  build() {
    Row({ space: 10 }) {
      listItemIcon(this.item.type)
      Column({ space: 4 }) {
        Row({ space: 8 }) {
          protocolPill(this.item.protocol)
          Text(this.item.title)
            .layoutWeight(100)
            .maxLines(1)
            .textOverflow({
              overflow: TextOverflow.Ellipsis
            })
            .fontSize(Svp2fp(18))
            .textAlign(TextAlign.Start)
        }
        .width('100%')
        .justifyContent(FlexAlign.Start)

        if (this.item.subtitle.length > 0) {
          Text(this.item.subtitle)
            .fontSize(14)
            .width('100%')
            .fontColor($r("sys.color.font_tertiary"))
            .maxLines(1)
            .textOverflow({
              overflow: TextOverflow.Ellipsis
            })
            .textAlign(TextAlign.Start)
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(100)
    }
    .backgroundStyle()
    .width('100%')
    .justifyContent(FlexAlign.Start)
    .onTouch((event) => {
      event.stopPropagation()
    })
  }
}
