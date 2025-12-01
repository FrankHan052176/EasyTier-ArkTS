import { AnimationType, DialogHub, TopDialogPriority } from '@hadss/dialoghub';
import { lane } from './util/Conversion';
import { curves } from '@kit.ArkUI';

class ToastParam {
  text: ResourceStr = '';
  symbol: Resource;
  level: number = 0
  constructor(text: ResourceStr, symbol: Resource, level: number) {
    this.text = text;
    this.symbol = symbol;
    this.level = level;
  }
}
function ToastColor(level: number): ResourceColor {
  switch (level) {
    case 1: return Color.Red;
    default: return $r("sys.color.font_primary");
  }
}
@Builder
function ToastBuilder(param: ToastParam) {
  Row() {
    SymbolGlyph(param.symbol)
      .fontSize(22)
      .symbolEffect(new HierarchicalSymbolEffect(EffectFillStyle.CUMULATIVE), true)
      .fontColor([ToastColor(param.level)])
    Row() {
      Text(param.text)
        .fontColor(ToastColor(param.level))
        .fontSize(18)
        .maxLines(1)
        .textOverflow({overflow: TextOverflow.MARQUEE})
    }
    .layoutWeight(100)
    .alignItems(VerticalAlign.Center)
    .justifyContent(FlexAlign.Center)
    .padding({
      left: 10, right: 10
    })
  }
  .alignItems(VerticalAlign.Center)
  .justifyContent(FlexAlign.Start)
  .width(lane(2))
  .padding({
    top: 10,bottom: 10,
    left: 10, right: 10
  })
  .borderRadius(14)
  .backgroundColor(param.level > 0?"#FDD9D9":$r("sys.color.comp_background_primary"))
}

export function sendToast(text: ResourceStr = "N/A", symbol: Resource = $r("sys.symbol.ellipsis_message"), level: number = 0) {
  DialogHub.getToast()
    .setContent(wrapBuilder(ToastBuilder), new ToastParam(text, symbol, level))
    .setStyle({
      radius: 14,
      shadow: {
        radius: 14,
        type: ShadowType.BLUR,
        color: level > 0?"#FDD9D9":$r("sys.color.comp_background_primary")
      },
      backgroundColor: Color.Transparent
    })
    .setConfig({
      dialogPosition: {
        alignment: DialogAlignment.Top,
        offset: {
          dx: 0,
          dy: 8
        }
      }
    })
    .setDuration(1700)
    .setAnimation({ dialogAnimation: TransitionEffect.move(TransitionEdge.TOP).animation({duration: 300, curve: curves.springMotion(0.4, 0.7)}) })
    .build()
    .show()
}