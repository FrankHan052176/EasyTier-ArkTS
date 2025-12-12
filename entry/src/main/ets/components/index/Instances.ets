import { CompTitle } from './Basic'
import { LengthMetrics } from '@kit.ArkUI'
import { AppManager, Svp2fp } from '../../AppManager'
import { HMRouterMgr } from '@hadss/hmrouter'
import { HMRouterTransitions } from '@hadss/hmrouter-transitions'
import { lane } from '../../util/Conversion'

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
  @Local list_height: number = 0

  @Computed
  get CompSize() {
    return AppManager.layout.getCompSize("Instances")
  }

  @Computed
  get ConfigName() {
    return AppManager.data.configUUIDNameMap.get(AppManager.easytier.selected ?? "") ?? "未选择实例"
  }

  @Computed
  get ConfigUUID() {
    return AppManager.easytier.selected ?? "404"
  }

  @Computed
  get rowHeight() {
    return (lane(1)-24-16)/3
  }

  @Builder
  button() {
    Row({space: 4}) {
      Row() {
        SymbolGlyph($r("sys.symbol.star"))
          .fontSize(Svp2fp(this.rowHeight-20))
          .fontColor([$r("sys.color.font_secondary")])
      }
      .backgroundColor($r("sys.color.comp_background_tertiary"))
      .borderRadius(12)
      .alignItems(VerticalAlign.Center)
      .justifyContent(FlexAlign.Center)
      .size({width: this.rowHeight, height: this.rowHeight})
      Row() {
        SymbolGlyph($r("sys.symbol.square_and_pencil"))
          .fontSize(Svp2fp(this.rowHeight-20))
          .fontColor([$r("sys.color.font_secondary")])
      }
      .backgroundColor($r("sys.color.comp_background_tertiary"))
      .borderRadius(12)
      .alignItems(VerticalAlign.Center)
      .justifyContent(FlexAlign.Center)
      .size({width: this.rowHeight, height: this.rowHeight})
    }
    .padding({top: 2, bottom: 2})
    .width('100%')
    .justifyContent(FlexAlign.SpaceBetween)
    .height(this.rowHeight)
  }

  build() {
    Column() {
      Column({ space: 8 }) {
        Row({ space: 4 }) {
          Row() {
            SymbolGlyph($r("sys.symbol.protein"))
              .fontSize(Svp2fp(this.rowHeight-20))
              .fontColor([$r("sys.color.brand")])
          }
          .size({width: this.rowHeight, height: this.rowHeight})
          .backgroundColor($r("sys.color.comp_background_tertiary"))
          .borderRadius(12)
          .alignItems(VerticalAlign.Center)
          .justifyContent(FlexAlign.Center)
          Column({ space: 4 }) {
            Text(this.ConfigName)
              .maxFontSize(40)
              .minFontSize(8)
              .layoutWeight(100)
              .maxLines(1)
              .textOverflow({
                overflow: TextOverflow.Ellipsis
              })
              .textAlign(TextAlign.Start)

            Text(this.ConfigUUID.slice(0, 7))
              .fontSize(Svp2fp(this.rowHeight/2-8))
              .width('100%')
              .fontColor($r("sys.color.font_tertiary"))
              .maxLines(1)
              .textAlign(TextAlign.Start)
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(100)
          .padding({top: 2, bottom: 2})
        }
        .borderRadius(12)
        .width('100%')
        .justifyContent(FlexAlign.Start)
        .height(this.rowHeight)
        .backgroundColor($r("sys.color.comp_background_primary"))




        Row({space: 4}) {
          Row() {
            SymbolGlyph($r("sys.symbol.switch_square"))
              .fontSize(Svp2fp(this.rowHeight-20))
              .fontColor([$r("sys.color.font_secondary")])
          }
          .size({width: this.rowHeight, height: this.rowHeight})
          .backgroundColor($r("sys.color.comp_background_tertiary"))
          .borderRadius(12)
          .alignItems(VerticalAlign.Center)
          .justifyContent(FlexAlign.Center)
          Column({ space: 4 }) {
            Text("切换实例")
              .maxFontSize(40)
              .minFontSize(8)
              .layoutWeight(100)
              .maxLines(1)
              .textOverflow({
                overflow: TextOverflow.Ellipsis
              })
              .textAlign(TextAlign.Start)

            Text("共"+AppManager.data.configUUIDMap.size+"个")
              .fontSize(Svp2fp(this.rowHeight/2-8))
              .width('100%')
              .fontColor($r("sys.color.font_tertiary"))
              .maxLines(1)
              .textAlign(TextAlign.Start)
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(100)
          .padding({top: 2, bottom: 2})
        }
        .width('100%')
        .justifyContent(FlexAlign.Start)
        .height(this.rowHeight)
      }
      .padding(12)
    }
    .comp_bg()
  }
}