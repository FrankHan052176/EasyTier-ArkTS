import { Config, exit_node, route } from "../../util/config/ETConfig"
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
export struct ExitNodes {
  @Param @Require config: Config
  @Local item_width: number = 160
  @Local item_height: number = 60
  @Local edit: exit_node = new exit_node()
  @Local add: exit_node = new exit_node()
  @Local old: exit_node = new exit_node()
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
  Sheet(network: exit_node) {
    Column() {
      Row() {
        TextInput({text: network.ipv4})
          .padding({left: 1, right: 1, top: 5, bottom: 5})
          .backgroundColor(Color.Transparent)
          .border(underline)
          .width("90%")
          .textAlign(TextAlign.Center)
          .onChange((value: string) => {
            network.ipv4 = value
          })
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
      Text(`
请设置虚拟IP，如10.0.0.2
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
  network(value: exit_node) {
    Stack({alignContent: Alignment.TopStart}) {
      Text(value.ipv4)
        .height('100%')
        .width('100%')
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .fontSize(14)
        .fontColor($r("sys.color.font_primary"))
        .textAlign(TextAlign.Center)
        .padding({left: 10, right: 10})
        .geometryTransition(this.config.instance_id+"_en_"+value.toString())
    }
  }

  @Builder
  addContent() {
    Text('新增路由')
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
        Text("出口节点")
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
          ForEach(Array.from(Manager.exit_nodes), (value:exit_node) => {
            FancyItem({
              item_width: this.item_width,
              item_height: this.item_height,
              contentBuilder: () => {
                this.network(value)
              },
              sheetBuilder: () => {
                this.Sheet(this.edit)
              },
              clickCallback: () => {
                if (!this.config.exit_nodes.delete(value)) {
                  this.config.exit_nodes.add(value)
                }
              },
              changeCallback: (isOn) => {
                if (isOn) {
                  this.config.exit_nodes.add(value)
                }else {
                  this.config.exit_nodes.delete(value)
                }
              },
              isSelected: () => {
                return this.config.exit_nodes.has(value)
              },
              menuEditCallback: () => {
                this.edit = new exit_node().from(value)
                this.old = new exit_node().from(value)
              },
              menuDeleteCallback: () => {
                Manager.exit_nodes.delete(value)
                Manager.configs.forEach((config) => {
                  config.exit_nodes.delete(value)
                })
              },
              sheetConfirmCallback: () => {
                Manager.configs.forEach((value) => {
                  if (value.exit_nodes.delete(this.old!)) {
                    value.exit_nodes.add(new exit_node().from(this.edit!))
                    this.old.reset()
                  }
                })
                Manager.exit_nodes.delete(this.old!)
                Manager.exit_nodes.add(this.edit!)
              },
              sheetTitleFunc: () => {
                return "编辑出口节点"
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
              this.Sheet(this.add!)
            },
            sheetConfirmCallback: () => {
              if (!Manager.exit_nodes.has(this.add!)) {
                Manager.exit_nodes.add(new exit_node().from(this.add!))
                this.add.reset()
              }
            },
            sheetTitleFunc: () => {
              return "新增出口节点"
            }
          })
        }
        .borderRadius(10)
        .maintainVisibleContentPosition(true)
        .scrollBar(BarState.Off)
        .lanes(this.list_lanes, 10)
        .listDirection(Axis.Vertical)
        .width((this.list_lanes-1)*(this.item_width+10)+this.item_width)
        .height(betterHeight(Manager.exit_nodes.size, this.list_lanes, this.item_height))
      }else {
        List({space: 10, initialIndex: 0}) {
          ForEach(Array.from(this.config.exit_nodes), (value:exit_node) => {
            ListItem() {
              Text(`${value.ipv4}`)
                .fontSize(14)
                .padding(10)
                .borderRadius(10)
                .backgroundColor($r("sys.color.interactive_hover"))
                .geometryTransition(this.config.instance_id+"_en_"+value.toString())
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