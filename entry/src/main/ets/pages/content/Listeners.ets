import Manager from "../../Manager"
import { Config, listener, Protocol, protocolColor } from "../../util/config/ETConfig"
import { FancyItem } from "../Components"
import { LengthMetrics } from "@kit.ArkUI"
import { betterHeight } from "../../util/Conversion"

let protocols = [Protocol.TCP, Protocol.UDP, Protocol.QUIC, Protocol.WS, Protocol.WSS, Protocol.WG]
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
export struct Listeners {
  @Param @Require config: Config
  @Local item_width: number = 160
  @Local item_height: number = 60
  @Local edit: listener = new listener()
  @Local add: listener = new listener()
  @Local old: listener = new listener()
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
  Sheet(Listener: listener) {
    Column() {
      Row() {
        TextPicker({ range: protocols, selected: protocols.indexOf(Listener._protocol)})
          .onChange((_value: string | string[], index: number | number[]) => {
            Listener._protocol = protocols[index as number]
          })
          .canLoop(false)
          .defaultPickerItemHeight(36)
          .width(70)
        Text("://")
          .fontSize(18)
          .margin({left: 2, right: 2})
        TextInput({text: Listener._domain})
          .padding({left: 1, right: 1, top: 5, bottom: 5})
          .backgroundColor(Color.Transparent)
          .border(underline)
          .width(150)
          .textAlign(TextAlign.Center)
          .onChange((value: string) => {
            Listener._domain = value
          })
        Text(":")
          .fontSize(18)
          .margin({left: 2, right: 2})
        TextInput({text: ""+Listener._port})
          .padding({left: 1, right: 1, top: 5, bottom: 5})
          .type(InputType.Number)
          .backgroundColor(Color.Transparent)
          .border(underline)
          .maxLength(5)
          .width(60)
          .textAlign(TextAlign.Center)
          .onChange((value: string) => {
            Listener._port = Number.parseInt(value)
          })
      }
      .width('100%')
      Text(`
协议、域名、端口请分别设置
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
  Content(value: listener) {
    Stack({alignContent: Alignment.TopStart}) {
      Row() {
        Text(value._protocol.toUpperCase())
          .fontColor($r("sys.color.font_on_primary"))
          .fontSize(12)
          .width(40)
          .borderRadius(6)
          .backgroundColor(protocolColor(value._protocol))
          .padding({top: 3, bottom: 3, right: 5, left: 5})
          .textAlign(TextAlign.Center)
      }
      .alignItems(VerticalAlign.Center)
      .justifyContent(FlexAlign.End)
      .width('100%')
      .margin({bottom: 10})
      .offset({
        x: -3,
        y: 3
      })
      Text(value._domain+":"+value._port)
        .height('100%')
        .width('100%')
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .fontSize(14)
        .fontColor($r("sys.color.font_primary"))
        .textAlign(TextAlign.Center)
        .padding({left: 10, right: 10})
        .geometryTransition(this.config.instance_id+"_listener_"+value.toString())
    }
  }

  @Builder
  addContent() {
    Text('新增监听地址')
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
        Text("监听地址")
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
          ForEach(Array.from(Manager.listeners), (value:listener) => {
            FancyItem({
              item_width: this.item_width,
              item_height: this.item_height,
              contentBuilder: () => {
                this.Content(value)
              },
              sheetBuilder: () => {
                this.Sheet(this.edit)
              },
              clickCallback: () => {
                if (!this.config.listeners.delete(value)) {
                  this.config.listeners.add(value)
                }
              },
              changeCallback: (isOn) => {
                if (isOn) {
                  this.config.listeners.add(value)
                }else {
                  this.config.listeners.delete(value)
                }
              },
              isSelected: () => {
                return this.config.listeners.has(value)
              },
              menuEditCallback: () => {
                this.edit = new listener().from(value)
                this.old = new listener().from(value)
              },
              menuDeleteCallback: () => {
                Manager.listeners.delete(value)
              },
              sheetConfirmCallback: () => {
                Manager.configs.forEach((value) => {
                  if (value.listeners.delete(this.old!)) {
                    value.listeners.add(new listener().from(this.edit!))
                    this.old.reset()
                  }
                })
                Manager.listeners.delete(this.old!)
                Manager.listeners.add(this.edit!)
              },
              sheetTitleFunc: () => {
                return "编辑监听地址"
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
              if (!Manager.listeners.has(this.add!)) {
                Manager.listeners.add(new listener().from(this.add!))
                this.add.reset()
              }
            },
            sheetTitleFunc: () => {
              return "新增监听地址"
            }
          })
        }
        .borderRadius(10)
        .maintainVisibleContentPosition(true)
        .scrollBar(BarState.Off)
        .lanes(this.list_lanes, 10)
        .listDirection(Axis.Vertical)
        .width((this.list_lanes-1)*(this.item_width+10)+this.item_width)
        .height(betterHeight(Manager.listeners.size, this.list_lanes, this.item_height))
      }else {
        List({space: 10, initialIndex: 0}) {
          ForEach(Array.from(this.config.listeners), (value:listener) => {
            ListItem() {
              Text(`${value._protocol}://${value._domain}:${value._port}`)
                .fontSize(14)
                .padding(10)
                .borderRadius(10)
                .backgroundColor($r("sys.color.interactive_hover"))
                .geometryTransition(this.config.instance_id+"_listener_"+value.toString())
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