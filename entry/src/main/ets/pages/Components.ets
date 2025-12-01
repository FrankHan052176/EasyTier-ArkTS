import { SymbolGlyphModifier } from "@kit.ArkUI"
import { BusinessError, pasteboard } from "@kit.BasicServicesKit"
import { Logger } from "../util/Logger"
import { HdsNavigationMenuItemOptions, IconStyleMode } from "@kit.UIDesignKit"
import { symbolWithSize } from "./hmrouter/HomePage"

@Builder
export function SharedPeersSheet() {
  // List({space: 10}) {
  //   if (Manager.sharedPeers.size > 0) {
  //     LazyForEach([], (value: null) => {
  //       ListItem() {
  //         Stack({alignContent: Alignment.TopStart}) {
  //           Row() {
  //             Text(value._protocol.toUpperCase())
  //               .fontColor($r("sys.color.font_on_primary"))
  //               .fontSize(12)
  //               .borderRadius(6)
  //               .width(40)
  //               .backgroundColor(protocolColor(value._protocol))
  //               .padding({top: 3, bottom: 3, right: 5, left: 5})
  //               .textAlign(TextAlign.Center)
  //           }
  //           .alignItems(VerticalAlign.Center)
  //           .justifyContent(FlexAlign.End)
  //           .width('100%')
  //           .offset({
  //             x: 6,
  //             y: -6
  //           })
  //           Row() {
  //             Progress({
  //               value: value.usage_percentage, total: 100, type: ProgressType.Linear,
  //             })
  //               .width('100%')
  //               .color(getLoadColor(value.usage_percentage))
  //               .offset({
  //                 y: 6
  //               })
  //           }
  //           .height('100%')
  //           .width('100%')
  //           .justifyContent(FlexAlign.Center)
  //           .alignItems(VerticalAlign.Bottom)
  //           Row() {
  //             Text(value.name)
  //               .fontSize(12)
  //               .maxLines(2)
  //               .width(135)
  //             Column() {
  //               Text(value.allow_relay?"可转发":"禁转发")
  //                 .fontColor($r("sys.color.font_on_primary"))
  //                 .fontSize(12)
  //                 .borderRadius(6)
  //                 .width(50)
  //                 .backgroundColor(value.allow_relay?$r("sys.color.confirm"):$r("sys.color.warning"))
  //                 .padding({top: 3, bottom: 3, right: 5, left: 5})
  //                 .textAlign(TextAlign.Center)
  //               Text(value.version)
  //                 .fontColor($r("sys.color.font_on_primary"))
  //                 .fontSize(12)
  //                 .borderRadius(6)
  //                 .width(50)
  //                 .backgroundColor($r("sys.color.comp_background_emphasize"))
  //                 .padding({top: 3, bottom: 3, right: 5, left: 5})
  //                 .textAlign(TextAlign.Center)
  //             }
  //             .margin({left: 5})
  //             .alignItems(HorizontalAlign.Center)
  //             .justifyContent(FlexAlign.SpaceBetween)
  //             .height('100%')
  //             Row() {
  //               Text(""+value.current_connections+"/"+value.max_connections)
  //                 .margin({bottom: 5})
  //                 .width(68)
  //                 .textAlign(TextAlign.End)
  //               Checkbox()
  //                 .select(Manager.peers.has(value))
  //                 .selectedColor($r("sys.color.comp_background_emphasize"))
  //                 .shape(CheckBoxShape.CIRCLE)
  //                 .onChange((isOn: boolean) => {
  //                   if (isOn) {
  //                     Manager.peers.add(value)
  //                   }else {
  //                     Manager.peers.delete(value)
  //                     Manager.configs.forEach((cfg) => {
  //                       cfg.peer.delete(value)
  //                     })
  //                   }
  //                 })
  //                 .clickEffect({
  //                   level: ClickEffectLevel.LIGHT,
  //                   scale: 1.0
  //                 })
  //                 .margin({top: 20})
  //                 .zIndex(2)
  //             }
  //             .height('100%')
  //             .alignItems(VerticalAlign.Center)
  //             .justifyContent(FlexAlign.SpaceBetween)
  //             .layoutWeight(100)
  //             .margin({left: 5})
  //           }
  //           .width('100%')
  //           .height('100%')
  //           .alignItems(VerticalAlign.Center)
  //           .justifyContent(FlexAlign.Start)
  //         }
  //         .width("100%")
  //         .height(60)
  //         .borderRadius(10)
  //         .backgroundColor($r("sys.color.background_secondary"))
  //         .padding(10)
  //       }
  //       .clickEffect({
  //         level: ClickEffectLevel.LIGHT
  //       })
  //     })
  //     ListItem() {
  //     }
  //     .width('100%')
  //     .height(50)
  //   }else {
  //     ListItem() {
  //       Text("无社区共享节点")
  //         .fontSize(14)
  //         .width("100%")
  //     }
  //   }
  // }
  // .alignListItem(ListItemAlign.Start)
  // .padding({left: 10, right: 10})
  // .width("100%")
  // .height("100%")
  // .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.START, SafeAreaEdge.BOTTOM])
}

export function MenuButton(value: string | Resource, symbol: Resource, callback: () => void): NavigationMenuItem {
  return {'value': value, 'symbolIcon': new SymbolGlyphModifier(symbol), 'action': ()=> {
    callback()
  }}
}

export function HdsMenuButton(value: ResourceStr, symbol: Resource, callback: () => void): HdsNavigationMenuItemOptions {
  return {
    content: {
      icon: symbolWithSize(symbol, 24),
      label: value,
      action: ()=>{
        callback()
      },
      type: IconStyleMode.LARGE
    }
  }
}

@ComponentV2
export struct ToolButton {
  @Param @Require symbol: Resource
  @Param buttonSize: number = 40
  @Param symbolScale: number = 0.6
  @Param bgColor: ResourceColor = $r("sys.color.comp_background_tertiary")
  @Param symbolColor: Array<ResourceColor> = [$r("sys.color.font_primary")]
  build() {
    Button({ type: ButtonType.Circle }) {
      SymbolGlyph(this.symbol)
        .fontColor(this.symbolColor)
        .fontSize(this.buttonSize*this.symbolScale)
        .animation({
          curve: Curve.EaseIn,
          duration: 300
        })
    }
    .width(this.buttonSize).height(this.buttonSize)
    .buttonStyle(ButtonStyleMode.NORMAL)
    .backgroundColor(this.bgColor)
    .clickEffect({
      level: ClickEffectLevel.LIGHT,
      scale: 0.8
    })
    .animation({
      curve: Curve.EaseIn,
      duration: 300
    })
  }
}

@ComponentV2
export struct ToolButtonWithText {
  @Param @Require symbol: Resource
  @Param @Require text: string
  @Param bgColor: ResourceColor = $r("sys.color.comp_background_tertiary")
  @Param textColor: ResourceColor = $r("sys.color.font_primary")
  @Param symbolColor: Array<ResourceColor> = [$r("sys.color.font_primary")]
  @Param symbolSize: number = 24
  @Param textSize: number = 18

  build() {
    Button({ type: ButtonType.Capsule }) {
      Row() {
        SymbolGlyph(this.symbol)
          .fontColor(this.symbolColor)
          .fontSize(this.symbolSize)
        Text(this.text)
          .fontColor(this.textColor)
          .fontSize(this.textSize)
      }
      .justifyContent(FlexAlign.SpaceAround)
    }
    .padding({left: 10, right: 10})
    .height(this.symbolSize/6*10)
    .buttonStyle(ButtonStyleMode.NORMAL)
    .backgroundColor(this.bgColor)
    .clickEffect({
      level: ClickEffectLevel.LIGHT,
      scale: 0.8
    })
  }
}

@ComponentV2
export struct ToolButtonWithPaste {
  @Param pasteCallback: (value: string) => void = () => {}
  build() {
    PasteButton({
      buttonType: ButtonType.Circle,
      text: undefined
    })
      .padding({left: 10, right: 10})
      .height(40)
      .onClick((_event, result) => {
        if (PasteButtonOnClickResult.SUCCESS === result) {
          pasteboard.getSystemPasteboard().getData((err: BusinessError, pasteData: pasteboard.PasteData) => {
            if (err) {
              console.error(`Failed to get paste data. Code is ${err.code}, message is ${err.message}`);
              return;
            }
            this.pasteCallback(pasteData.getPrimaryText())
          });
        }else {
          Logger.debug("failed get perm")
        }
      })
  }
}

@Builder
function gradientText(size: number = 36, text: string | Resource | undefined = 'EasyTier', weight: number | FontWeight | ResourceStr = FontWeight.Bold, angle: string | number | undefined = 225) {
  Stack() {
    Row() {
      Text(text)
        .fontWeight(weight)
        .minFontSize(1)
        .maxFontSize(100)
        .maxLines(1)
        .blendMode(BlendMode.DST_IN, BlendApplyType.OFFSCREEN)
        .clip(false)
        .padding(5)
    }
    .linearGradient({
      colors:[
        ['rgba(255,200,50,1)', 0.3],
        ['rgba(0,230,118,1)', 1]
      ],
      angle: angle
    })
    .blendMode(BlendMode.SRC_OVER, BlendApplyType.OFFSCREEN)
    .justifyContent(FlexAlign.Center)
  }
  .layoutWeight(size)
  .clip(false)
}
