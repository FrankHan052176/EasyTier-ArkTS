import { AppManager, Svp2fp } from '../../AppManager'
import { CompTitle } from './Basic'
import { LengthMetrics } from '@kit.ArkUI'
import { sendToast } from '../../ToastUtil'

@Extend(Column)
function comp_bg() {
  .width('100%')
  .height('100%')
  .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
}

@ComponentV2
export struct Favorite {
  @Local text_height: number = 0
  @Local comp_width: number = 0
  @Local comp_height: number = 0
  @Local trigger: number = 0

  @Computed
  get CompSize() {
    return AppManager.layout.getCompSize("Favorite")
  }

  @Computed
  get isRunning() {
    return AppManager.easytier.isFavoritesRunning() ? 1 : 0
  }

  build() {
    Column() {
      CompTitle("收藏实例", 'rgba(255,200,50,1)', () => {
        return -1
      })
      Flex({
        wrap: FlexWrap.Wrap,
        space: {
          main: LengthMetrics.vp(10),
          cross: LengthMetrics.vp(10)
        },
        alignItems: ItemAlign.Center,
        alignContent: FlexAlign.Center,
        direction: FlexDirection.Column
      }) {
        if (AppManager.data.favoriteInstance !== undefined) {
          Row() {
            SymbolGlyph(this.isRunning ? $r("sys.symbol.pause_round_triangle_fill") :
              $r("sys.symbol.play_round_triangle_fill"))
              .align(Alignment.Center)
              .fontSize(Svp2fp(this.CompSize.lane_w == 1 ?
                (this.CompSize.lane_h == 2 ? this.comp_height * 0.3 : this.comp_height * 0.5) :
                Math.min(this.comp_height * 0.8, this.comp_width * 0.4)))
              .fontColor(['rgba(255,200,50,1)'])
              .symbolEffect(new ReplaceSymbolEffect(EffectScope.WHOLE), this.isRunning + this.trigger)
              .onClick(() => {
                if (this.isRunning) {
                  AppManager.easytier.stop()
                } else {
                  if (AppManager.easytier.runningNetworks.size > 0) {
                    AppManager.easytier.stop()
                  }
                  if (!AppManager.easytier.start(AppManager.data.favoriteInstance)) {
                    sendToast("Amazing! 收藏的实例不存在", $r("sys.symbol.exclamationmark_circle"), 1)
                  }
                }
                if (this.trigger === 0) {
                  this.trigger = 1
                }
              })
          }
          .width(this.CompSize.lane_w == 1 ? '100%' : this.comp_width * 0.4)
          .height(this.CompSize.lane_w == 2 ? "100%" : this.comp_height * 0.5)
          .alignItems(VerticalAlign.Center)
          .justifyContent(FlexAlign.Center)

          Column() {
            Text(AppManager.data.configUUIDNameMap.get(AppManager.data.favoriteInstance))
              .width('100%')
              .textAlign(this.CompSize.lane_w == 2 ? TextAlign.Start : TextAlign.Center)
              .fontSize(this.CompSize.lane_w == 1 && this.CompSize.lane_h == 1 ? Svp2fp(this.text_height - 8) :
                Svp2fp(this.text_height * 0.2))
              .maxLines(2)
              .textOverflow({
                overflow: TextOverflow.Ellipsis
              })
            Text(AppManager.data.favoriteInstance)
              .width('100%')
              .textAlign(this.CompSize.lane_w == 2 ? TextAlign.Start : TextAlign.Center)
              .maxFontSize(12)
              .minFontSize(8)
              .fontColor($r("sys.color.font_secondary"))
              .maxLines(1)
              .textOverflow({
                overflow: TextOverflow.Ellipsis
              })
          }
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
          .width(this.CompSize.lane_w == 1 ? '100%' : this.comp_width * 0.6)
          .height(this.CompSize.lane_w == 2 ? '100%' : (this.comp_height * 0.5 - 10))
          .onAreaChange((a, b) => {
            this.text_height = (b.height.valueOf() as number) - 20
          })
        }
      }
      .width('100%')
      .layoutWeight(100)
      .padding(10)
      .onAreaChange((a, b) => {
        this.comp_width = (b.width.valueOf() as number) - 20
        this.comp_height = (b.height.valueOf() as number) - 20
      })
    }
    .comp_bg()
  }
}