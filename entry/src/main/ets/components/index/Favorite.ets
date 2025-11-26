import { AppManager, Sfp2px, Sfp2vp, Svp2fp } from '../../AppManager'
import { lane } from '../../util/Conversion'
import { EventHelper } from '../../util/EventHelper'
import { CompTitle } from './Basic'
import { LengthMetrics } from '@kit.ArkUI'

@Extend(Column)
function comp_bg() {
  .width('100%')
  .height('100%')
  .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
}

@ComponentV2
export struct Favorite {
  @Local name: string | undefined
  @Local instanceId: string | undefined
  @Local text_height: number = 0
  @Local comp_width: number = 0
  @Local comp_height: number = 0

  aboutToAppear(): void {
    this.instanceId = AppManager.data.favoriteInstance
    this.name = AppManager.data.configUUIDNameMap.get(this.instanceId ?? "")
    EventHelper.emitterListener("favorite_update", () => {
      this.instanceId = AppManager.data.favoriteInstance
      this.name = AppManager.data.configUUIDNameMap.get(this.instanceId ?? "")
    })
  }

  @Computed
  get CompSize() {
    return AppManager.layout.getCompSize("Favorite")
  }

  build() {
    Column() {
      CompTitle("收藏实例", 'rgba(255,200,50,1)', ()=>{return -1})
      Flex({wrap: FlexWrap.Wrap, space: {
        main: LengthMetrics.vp(10),
        cross: LengthMetrics.vp(10)
      }, alignItems: ItemAlign.Center, alignContent: FlexAlign.Center, direction: FlexDirection.Column}) {
        if (this.instanceId !== undefined) {
          Row() {
            SymbolGlyph($r("sys.symbol.play_round_triangle_fill"))
              .align(Alignment.Center)
              .fontSize(Svp2fp(this.CompSize.lane_w==1?(this.CompSize.lane_h==2?this.comp_height*0.3:this.comp_height*0.5):Math.min(this.comp_height*0.8,this.comp_width*0.4)))
              .fontColor(['rgba(255,200,50,1)'])
          }
          .width(this.CompSize.lane_w==1?'100%':this.comp_width*0.4)
          .height(this.CompSize.lane_w==2?"100%":this.comp_height*0.5)
          .alignItems(VerticalAlign.Center)
          .justifyContent(FlexAlign.Center)
          Column() {
            Text(this.name)
              .width('100%')
              .textAlign(this.CompSize.lane_w==2?TextAlign.Start:TextAlign.Center)
              .fontSize(this.CompSize.lane_w==1 && this.CompSize.lane_h==1?Svp2fp(this.text_height-8):Svp2fp(this.text_height*0.2))
              .maxLines(2)
              .textOverflow({
                overflow: TextOverflow.Ellipsis
              })
            Text(this.instanceId)
              .width('100%')
              .textAlign(this.CompSize.lane_w==2?TextAlign.Start:TextAlign.Center)
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
          .width(this.CompSize.lane_w==1?'100%':this.comp_width*0.6)
          .height(this.CompSize.lane_w==2?'100%':(this.comp_height*0.5-10))
          .onAreaChange((a,b) => {
            this.text_height = (b.height.valueOf() as number)-20
          })
        }
      }
      .width('100%')
      .layoutWeight(100)
      .padding(10)
      .onAreaChange((a,b) => {
        this.comp_width = (b.width.valueOf() as number)-20
        this.comp_height = (b.height.valueOf() as number)-20
      })
    }
    .comp_bg()
  }
}