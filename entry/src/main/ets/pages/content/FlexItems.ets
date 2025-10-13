import Manager from "../../Manager"
import { cidr, Config, exit_node, listener, network_identity, peer, route } from "../../util/config/ETConfig"
import { ItemBuilder } from "../../util/ItemBuilders"
import { SafeLightWeightSet } from "../../util/SafeLightWeightSet"
import { LengthMetrics } from "@kit.ArkUI"

export enum ItemSize {
  SMALL,NORMAL,BIG
}
export type itemType = peer | network_identity | cidr | listener | string | route | exit_node
@ComponentV2
export struct FlexItems {
  @Param @Require config: Config
  @Param @Require title: string
  @Param @Require items: SafeLightWeightSet<itemType>
  @Param @Require compSize: ItemSize
  @Param @Require clickCallback: (item: itemType) => void
  @Param @Require selectedFunc: (item: itemType) => boolean

  @Computed
  get comp_width() {
    return Manager.width>=Manager.height*0.625?360:Manager.width-20
  }

  build() {
    Column() {
      Row() {
        Text(this.title)
          .fontSize(17)
          .fontColor($r("sys.color.font_primary"))
        Row() {
          // TODO 切换大小

        }
        .onClick(() => {
          animateToImmediately({
            curve: Curve.LinearOutSlowIn,
            duration: 300
          }, () => {

          })
        })
        .clickEffect({
          level: ClickEffectLevel.LIGHT
        })
      }
      .justifyContent(FlexAlign.SpaceBetween)
      .width('100%')
      .padding({left: 5, bottom: 10})
      Flex({space: {
        main: LengthMetrics.vp(10), cross: LengthMetrics.vp(10)
      }}) {
        LazyForEach(this.items, (item: itemType) => {
          ItemBuilder({item: item, itemSize: this.compSize, isSelected: this.selectedFunc(item), itemWidth: (this.comp_width-30)/2})
            .onClick(() => {
              this.clickCallback(item)
            })
        })
      }
      .width('100%')
    }
    .width(this.comp_width)
    .alignItems(HorizontalAlign.Center)
    .borderRadius(18)
    .backgroundColor($r("sys.color.comp_background_primary"))
    .padding({top: 15, left: 10, right: 10, bottom: 10})
    .clip(true)
  }
}