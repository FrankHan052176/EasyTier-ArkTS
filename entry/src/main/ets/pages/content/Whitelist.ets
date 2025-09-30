import { Config, cidr } from "../../util/config/ETConfig"
import { FancyItem } from "../Components"
import { LengthMetrics } from "@kit.ArkUI"
import Manager from "../../Manager"
import { betterHeight } from "../../util/Conversion"

const underline: BorderOptions = {
  width: {
    start: LengthMetrics.vp(0),
    end: LengthMetrics.vp(0),
    top: LengthMetrics.vp(0),
    bottom: LengthMetrics.vp(1)
  },
  color: {
    bottom: $r("sys.color.comp_divider")
  },
  radius: {
    bottomStart: LengthMetrics.vp(0),
    bottomEnd: LengthMetrics.vp(0)
  },
  style: {
    bottom: BorderStyle.Solid
  }
}

const minWidth = 350

@ComponentV2
export struct Whitelist {
  @Param @Require config: Config
  @Local item_width: number = 160
  @Local item_height: number = 60
  @Local edit: string = ""
  @Local add: string = ""
  @Local old: string = ""
  @Local isBig: boolean = false

  @Computed
  get comp_width() {
    return Manager.width>=Manager.height*0.625?minWidth:Manager.width-20
  }

  @Computed
  get list_lanes() {
    return Math.min(Math.floor(this.comp_width/this.item_width), 5);
  }

  @Builder
  Sheet(isEdit: boolean) {
    Column() {
      Row() {
        TextInput()
          .padding({left: 1, right: 1, top: 5, bottom: 5})
          .backgroundColor(Color.Transparent)
          .border(underline)
          .width('80%')
          .textAlign(TextAlign.Center)
          .onChange((value: string) => {
            if (isEdit) {
              this.edit = value
            }else {
              this.add = value
            }
          })
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
      Text(`
请设置网络名
      `)
        .width('100%')
        .fontSize(14)
        .fontColor($r("sys.color.font_secondary"))
        .textAlign(TextAlign.Center)
      Blank()
        .width('100%')
        .height(100)
    }
    .width('90%')
  }

  @Builder
  content(value: string) {
    Stack({alignContent: Alignment.TopStart}) {
      Text(value)
        .height('100%')
        .width('100%')
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .fontSize(14)
        .fontColor($r("sys.color.font_primary"))
        .textAlign(TextAlign.Center)
        .padding({left: 10, right: 10})
        .geometryTransition(this.config.instance_id+"_wl_"+value.toString())
    }
  }

  @Builder
  addContent() {
    Text('新增白名单')
      .width('100%')
      .height('100%')
      .maxLines(2)
      .textOverflow({ overflow: TextOverflow.Ellipsis })
      .fontSize(16)
      .fontColor($r("sys.color.font_primary"))
      .textAlign(TextAlign.Center)
  }

  build() {
    Column() {
      Row() {
        Text("网络白名单")
          .textAlign(TextAlign.Start)
          .fontSize(18)
          .fontColor($r("sys.color.font_primary"))
        Row() {
          Text(this.isBig?"折叠":"展开")
            .fontSize(16)
            .fontColor($r("sys.color.font_primary"))
          SymbolGlyph(this.isBig?$r("sys.symbol.arrow_down_right_and_arrow_up_left"):$r("sys.symbol.arrow_up_left_and_arrow_down_right"))
            .fontColor([$r("sys.color.font_primary")])
            .width(18)
            .height(18)
            .effectStrategy(SymbolEffectStrategy.SCALE)
        }
        .onClick(() => {
          animateToImmediately({
            curve: Curve.LinearOutSlowIn,
            duration: 300
          }, () => {
            this.isBig = !this.isBig
          })
        })
        .clickEffect({
          level: ClickEffectLevel.LIGHT
        })
      }
      .justifyContent(FlexAlign.SpaceBetween)
      .width('100%')
      .padding({left: 5, bottom: 5})
      if (this.isBig) {
        List({space: 10, initialIndex: 0}) {
          ForEach(Array.from(this.config.flags.relay_network_whitelist.whitelist), (value:string) => {
            FancyItem({
              item_width: this.item_width,
              item_height: this.item_height,
              needCheckbox: false,
              contentBuilder: () => {
                this.content(value)
              },
              sheetBuilder: () => {
                this.Sheet(true)
              },
              menuEditCallback: () => {
                this.edit = value
                this.old = ""+value
              },
              menuDeleteCallback: () => {
                this.config.flags.relay_network_whitelist.whitelist.delete(value)
              },
              sheetConfirmCallback: () => {
                if (this.config.flags.relay_network_whitelist.whitelist.delete(this.old)) {
                  this.config.flags.relay_network_whitelist.whitelist.add(this.edit)
                  this.old = ""
                }
              },
              sheetTitleFunc: () => {
                return "编辑白名单"
              }
            })
          })
          FancyItem({
            item_width: this.item_width,
            item_height: this.item_height,
            needCheckbox: false,
            needMenu: false,
            contentBuilder: () => {
              this.addContent()
            },
            sheetBuilder: () => {
              this.Sheet(false)
            },
            sheetConfirmCallback: () => {
              if (!this.config.flags.relay_network_whitelist.whitelist.has(this.add) && this.add.match(/^\s*$/) === null) {
                this.config.flags.relay_network_whitelist.whitelist.add(this.add)
                this.add = ""
              }
            },
            sheetTitleFunc: () => {
              return "新增白名单"
            }
          })
        }
        .borderRadius(10)
        .maintainVisibleContentPosition(true)
        .scrollBar(BarState.Off)
        .lanes(this.list_lanes, 10)
        .listDirection(Axis.Vertical)
        .width((this.list_lanes-1)*(this.item_width+10)+this.item_width)
        .height(betterHeight(this.config.flags.relay_network_whitelist.whitelist.size, this.list_lanes, this.item_height))
      }else {
        List({space: 10, initialIndex: 0}) {
          ForEach(Array.from(this.config.flags.relay_network_whitelist.whitelist), (value:string) => {
            ListItem() {
              Text(`${value}`)
                .fontSize(14)
                .padding(10)
                .borderRadius(10)
                .backgroundColor($r("sys.color.interactive_hover"))
                .geometryTransition(this.config.instance_id+"_wl_"+value.toString())
            }
          })
        }
        .width("100%")
        .height(36)
        .maintainVisibleContentPosition(true)
        .scrollBar(BarState.Off)
        .listDirection(Axis.Horizontal)
      }
    }
    .width(this.comp_width)
    .alignItems(HorizontalAlign.Start)
    .borderRadius(18)
    .backgroundColor($r("sys.color.comp_background_primary"))
    .padding(10)
    .clip(true)
  }
}