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
export struct ProxyCIDRs {
  @Param @Require config: Config
  @Local item_width: number = 160
  @Local item_height: number = 60
  @Local edit: cidr = new cidr()
  @Local add: cidr = new cidr()
  @Local old: cidr = new cidr()
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
  Sheet(network: cidr) {
    Column() {
      Row() {
        TextInput({text: network.ipv4})
          .padding({left: 1, right: 1, top: 5, bottom: 5})
          .backgroundColor(Color.Transparent)
          .border(underline)
          .width(70)
          .textAlign(TextAlign.Center)
          .onChange((value: string) => {
            network.ipv4 = value
          })
        Text("/")
          .fontSize(18)
          .margin({left: 2, right: 2})
        TextInput({text: ""+network.mask})
          .padding({left: 1, right: 1, top: 5, bottom: 5})
          .type(InputType.Number)
          .backgroundColor(Color.Transparent)
          .border(underline)
          .maxLength(2)
          .width(30)
          .textAlign(TextAlign.Center)
          .onChange((value: string) => {
            network.mask = Number.parseInt(value)
          })
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
      Text(`
请设置网段，如10.0.0.0/24
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
  network(value: cidr) {
    Stack({alignContent: Alignment.TopStart}) {
      Text(value.ipv4+"/"+value.mask)
        .height('100%')
        .width('100%')
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .fontSize(14)
        .fontColor($r("sys.color.font_primary"))
        .textAlign(TextAlign.Center)
        .padding({left: 10, right: 10})
        .geometryTransition(this.config.instance_id+"_cidr_"+value.toString())
    }
  }

  @Builder
  addContent() {
    Text('新增CIDR')
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
        Text("子网代理")
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
          ForEach(Array.from(Manager.cidrs), (value:cidr) => {
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
                if (!this.config.proxy_network.delete(value)) {
                  this.config.proxy_network.add(value)
                }
              },
              changeCallback: (isOn) => {
                if (isOn) {
                  this.config.proxy_network.add(value)
                }else {
                  this.config.proxy_network.delete(value)
                }
              },
              isSelected: () => {
                return this.config.proxy_network.has(value)
              },
              menuEditCallback: () => {
                this.edit = new cidr().from(value)
                this.old = new cidr().from(value)
              },
              menuDeleteCallback: () => {
                Manager.cidrs.delete(value)
                Manager.configs.forEach((config) => {
                  config.proxy_network.delete(value)
                })
              },
              sheetConfirmCallback: () => {
                Manager.configs.forEach((value) => {
                  if (value.proxy_network.delete(this.old!)) {
                    value.proxy_network.add(new cidr().from(this.edit!))
                    this.old.reset()
                  }
                })
                Manager.cidrs.delete(this.old!)
                Manager.cidrs.add(this.edit!)
              },
              sheetTitleFunc: () => {
                return "编辑CIDR"
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
              if (!Manager.cidrs.has(this.add!)) {
                Manager.cidrs.add(new cidr().from(this.add!))
                this.add.reset()
              }
            },
            sheetTitleFunc: () => {
              return "新增CIDR"
            }
          })
        }
        .borderRadius(10)
        .maintainVisibleContentPosition(true)
        .scrollBar(BarState.Off)
        .lanes(this.list_lanes, 10)
        .listDirection(Axis.Vertical)
        .width((this.list_lanes-1)*(this.item_width+10)+this.item_width)
        .height(betterHeight(Manager.cidrs.size, this.list_lanes, this.item_height))
      }else {
        List({space: 10, initialIndex: 0}) {
          ForEach(Array.from(this.config.proxy_network), (value:cidr) => {
            ListItem() {
              Text(`${value.ipv4}/${value.mask}`)
                .fontSize(14)
                .padding(10)
                .borderRadius(10)
                .backgroundColor($r("sys.color.interactive_hover"))
                .geometryTransition(this.config.instance_id+"_cidr_"+value.toString())
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