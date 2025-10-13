import Manager from "../Manager";
import { ItemSize, itemType } from "../pages/content/FlexItems";
import { cidr, exit_node, listener, network_identity, peer, protocolColor, route } from "./config/ETConfig";
import { safePassword } from "./Conversion";

@ComponentV2
export struct ItemBuilder {
  @Param @Require item: itemType
  @Param @Require itemSize: ItemSize
  @Param @Require isSelected: boolean
  @Param @Require itemWidth: number
  @Local isHighlight: boolean = false
  @Local highlightPos: [number, number] = [-999, -999]

  build() {
    Stack({alignContent: Alignment.Center}) {
      Column() {
        if (this.item instanceof peer) {
          PeerBuilder({item: this.item, itemSize: this.itemSize})
        }else if (this.item instanceof network_identity) {
          ProfileBuilder({item: this.item, itemSize: this.itemSize})
        }else if (this.item instanceof cidr) {
          CidrBuilder({item: this.item, itemSize: this.itemSize})
        }else if (this.item instanceof listener) {
          ListenerBuilder({item: this.item, itemSize: this.itemSize})
        }else if (typeof this.item == "string") {
          WhiteListBuilder({item: this.item, itemSize: this.itemSize})
        }else if (this.item instanceof route) {
          RouteBuilder({item: this.item, itemSize: this.itemSize})
        }else if (this.item instanceof exit_node) {
          ExitNodeBuilder({item: this.item, itemSize: this.itemSize})
        }
      }
      .zIndex(3)
      .width('100%')
      .height('100%')
      .backgroundColor(Color.Transparent)
      .alignItems(HorizontalAlign.Center)
      .justifyContent(FlexAlign.Center)
      .onMouse((event) => {
        if (event.action == MouseAction.Press) {
          this.highlightPos = [event.x, event.y]
          this.isHighlight = true
        }else if (event.action == MouseAction.CANCEL || event.action == MouseAction.Release) {
          this.highlightPos = [-999, -999]
          this.isHighlight = false
        }
      })
      .onTouch((event) => {
        if (event.type == TouchType.Down) {
          this.highlightPos = [event.changedTouches[0].x, event.changedTouches[0].y]
          this.isHighlight = true
        }else if (event.type == TouchType.Cancel || event.type == TouchType.Up) {
          this.highlightPos = [-999, -999]
          this.isHighlight = false
        }
      })
      if (this.isHighlight) {
        Column()
          .zIndex(2)
          .width('100%')
          .height('100%')
          .borderRadius(12)
          .backgroundColor(Color.Transparent)
          .radialGradient({
            center: this.highlightPos,
            radius: this.itemWidth/3,
            colors: [
              [this.isSelected ? $r("app.color.selected_highlight_1") : $r("app.color.normal_highlight_1"), 0],
              [this.isSelected ? $r("app.color.selected_highlight_2") : $r("app.color.normal_highlight_2"), 0.15],
              [this.isSelected ? $r("app.color.selected_highlight_3") : $r("app.color.normal_highlight_3"), 0.4],
              [this.isSelected ? $r("app.color.selected_highlight_4") : $r("app.color.normal_highlight_4"), 0.65],
              [this.isSelected ? $r("app.color.selected_highlight_5") : $r("app.color.normal_highlight_5"), 0.8],
              [this.isSelected ? $r("app.color.selected_highlight_6") : $r("app.color.normal_highlight_6"), 0.9],
              [this.isSelected ? $r("app.color.selected_highlight_7") : $r("app.color.normal_highlight_7"), 1]
            ]
          })
          .transition(TransitionEffect.OPACITY.animation({
            duration: 400,
            curve: Curve.Ease
          }))
      }else {
        Column()
          .zIndex(1)
          .width('100%')
          .height('100%')
          .backgroundColor(this.isSelected?$r("app.color.selected_background"):$r("app.color.normal_background"))
          .transition(TransitionEffect.OPACITY.animation({
            duration: 400,
            curve: Curve.Ease
          }))
      }
    }
    .width(this.itemWidth)
    .height(80)
    .border({
      width: 1,
      color: this.isSelected?$r("app.color.selected_border"):$r("app.color.normal_border"),
      radius: 12
    })
    .shadow(this.isSelected?{
      radius: 30,
      color: $r("app.color.selected_shadow")
    }:{
      radius: 30,
      color: $r("app.color.normal_shadow")
    })
    .clip(true)
    .clickEffect({
      level: ClickEffectLevel.LIGHT,
      scale: 0.93
    })
    .animation({
      duration: 300,
      curve: Curve.Ease
    })
  }
}

@ComponentV2
export struct ProfileBuilder {
  @Param @Require item: network_identity
  @Param @Require itemSize: ItemSize

  build() {
    Column() {
      Row() {
        Text() {
          SymbolSpan($r('sys.symbol.person'))
            .fontColor([$r("sys.color.font_primary")])
        }
        .margin({right: 5})
        Text(this.item.network_name)
          .maxLines(1)
          .fontColor($r("sys.color.font_primary"))
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(100)
      }
      .width('100%')
      .padding({left: 13, right: 13})
      .alignItems(VerticalAlign.Center)
      .justifyContent(FlexAlign.Start)
      Divider()
        .width('100%')
        .color($r("sys.color.font_fourth"))
        .padding({left: 5, right: 5})
      Row() {
        Text() {
          SymbolSpan($r('sys.symbol.key_horizontal'))
            .fontColor([$r("sys.color.font_primary")])
        }
        .margin({right: 5})
        Text(safePassword(this.item.network_secret))
          .maxLines(1)
          .fontColor($r("sys.color.font_primary"))
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(100)
      }
      .width('100%')
      .padding({left: 13, right: 13})

    }
    .alignItems(HorizontalAlign.Center)
    .justifyContent(FlexAlign.SpaceBetween)
    .width('100%')
    .height('100%')
  }
}

@ComponentV2
export struct PeerBuilder {
  @Param @Require item: peer
  @Param @Require itemSize: ItemSize

  isSharedPeer(value: peer): boolean {
    return Manager.sharedPeers.has(value.toString())
  }

  isAllowRelay(value: peer): boolean {
    return Boolean(Manager.sharedPeers.get(value.toString())?.allow_relay)
  }

  getPeerText(value: peer): string {
    let peer = Manager.sharedPeers.get(value.toString())
    if (peer) {
      return peer.name
    }else {
      return value._domain
    }
  }

  build() {
    Stack({alignContent: Alignment.TopStart}) {
      Row() {
        Row() {
          if (this.isSharedPeer(this.item)) {
            Text(this.isAllowRelay(this.item)?"可转发":"禁转发")
              .fontColor($r("sys.color.font_on_primary"))
              .fontSize(12)
              .width(50)
              .borderRadius(8)
              .backgroundColor(this.isAllowRelay(this.item)?$r("sys.color.confirm"):$r("sys.color.warning"))
              .padding({top: 3, bottom: 3, right: 5, left: 5})
              .textAlign(TextAlign.Center)
              .margin({right: 5})
          }
          Text(this.item._protocol.toUpperCase())
            .fontColor($r("sys.color.font_on_primary"))
            .fontSize(12)
            .width(40)
            .borderRadius(8)
            .backgroundColor(protocolColor(this.item._protocol))
            .padding({top: 3, bottom: 3, right: 5, left: 5})
            .textAlign(TextAlign.Center)
        }
        Row() {
          if (!this.isSharedPeer(this.item)) {
            Text() {
              SymbolSpan($r('sys.symbol.position'))
                .fontColor([$r("sys.color.font_primary")])
                .fontSize(14)
            }
            Text(this.item._port.toString())
              .fontColor($r("sys.color.font_primary"))
              .fontSize(14)
              .padding({top: 3, bottom: 3, right: 5, left: 5})
              .textAlign(TextAlign.Center)
          }
        }
      }
      .alignItems(VerticalAlign.Top)
      .justifyContent(FlexAlign.SpaceBetween)
      .width('100%')
      .padding({top: 5, left: 5, right: 5})
      Row() {
        Row() {
          Text() {
            SymbolSpan($r('sys.symbol.worldclock'))
              .fontColor([$r("sys.color.font_primary")])
              .fontSize(14)
          }
          .margin({right: 5})
          Text(this.getPeerText(this.item))
            .maxLines(1)
            .fontSize(14)
            .fontColor($r("sys.color.font_primary"))
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(100)
        }
        .width('88%')
      }
      .alignItems(VerticalAlign.Center)
      .justifyContent(FlexAlign.Center)
      .height('100%')
      .width('100%')
    }
    .width('100%')
    .height('100%')
  }
}

@ComponentV2
export struct CidrBuilder {
  @Param @Require item: cidr
  @Param @Require itemSize: ItemSize

  build() {
    Row() {
      Text() {
        SymbolSpan($r('sys.symbol.list_bullet'))
          .fontColor([$r("sys.color.font_primary")])
      }
      .margin({right: 5})
      Text(this.item.toRawString())
        .maxLines(1)
        .fontColor($r("sys.color.font_primary"))
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(100)
    }
    .width('100%')
    .height('100%')
    .padding({left: 13, right: 13})
    .alignItems(VerticalAlign.Center)
    .justifyContent(FlexAlign.Start)
  }
}

@ComponentV2
export struct ListenerBuilder {
  @Param @Require item: listener
  @Param @Require itemSize: ItemSize

  build() {
    Stack({alignContent: Alignment.TopStart}) {
      Row() {
        Row() {
          Text(this.item._protocol.toUpperCase())
            .fontColor($r("sys.color.font_on_primary"))
            .fontSize(12)
            .width(40)
            .borderRadius(8)
            .backgroundColor(protocolColor(this.item._protocol))
            .padding({top: 3, bottom: 3, right: 5, left: 5})
            .textAlign(TextAlign.Center)
        }
        Row() {
          Text() {
            SymbolSpan($r('sys.symbol.position'))
              .fontColor([$r("sys.color.font_primary")])
              .fontSize(14)
          }
          Text(this.item._port.toString())
            .fontColor($r("sys.color.font_primary"))
            .fontSize(14)
            .padding({top: 3, bottom: 3, right: 5, left: 5})
            .textAlign(TextAlign.Center)
        }
      }
      .alignItems(VerticalAlign.Top)
      .justifyContent(FlexAlign.SpaceBetween)
      .width('100%')
      .padding({top: 5, left: 5, right: 5})
      Row() {
        Row() {
          Text() {
            SymbolSpan($r('sys.symbol.worldclock'))
              .fontColor([$r("sys.color.font_primary")])
              .fontSize(14)
          }
          .margin({right: 5})
          Text(this.item._domain)
            .maxLines(1)
            .fontSize(14)
            .fontColor($r("sys.color.font_primary"))
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(100)
        }
        .width('88%')
      }
      .alignItems(VerticalAlign.Center)
      .justifyContent(FlexAlign.Center)
      .height('100%')
      .width('100%')
    }
    .width('100%')
    .height('100%')
  }
}

@ComponentV2
export struct WhiteListBuilder {
  @Param @Require item: string
  @Param @Require itemSize: ItemSize

  build() {
    Row() {
      Text() {
        SymbolSpan($r('sys.symbol.person'))
          .fontColor([$r("sys.color.font_primary")])
      }
      .margin({right: 5})
      Text(this.item)
        .maxLines(1)
        .fontColor($r("sys.color.font_primary"))
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(100)
    }
    .width('100%')
    .height('100%')
    .padding({left: 13, right: 13})
    .alignItems(VerticalAlign.Center)
    .justifyContent(FlexAlign.Start)
  }
}

@ComponentV2
export struct RouteBuilder {
  @Param @Require item: route
  @Param @Require itemSize: ItemSize

  build() {
    Row() {
      Text() {
        SymbolSpan($r('sys.symbol.list_bullet'))
          .fontColor([$r("sys.color.font_primary")])
      }
      .margin({right: 5})
      Text(this.item.toString())
        .maxLines(1)
        .fontColor($r("sys.color.font_primary"))
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(100)
    }
    .width('100%')
    .height('100%')
    .padding({left: 13, right: 13})
    .alignItems(VerticalAlign.Center)
    .justifyContent(FlexAlign.Start)
  }
}

@ComponentV2
export struct ExitNodeBuilder {
  @Param @Require item: exit_node
  @Param @Require itemSize: ItemSize

  build() {
    Row() {
      Text() {
        SymbolSpan($r('sys.symbol.local_fill'))
          .fontColor([$r("sys.color.font_primary")])
      }
      .margin({right: 5})
      Text(this.item.toString())
        .maxLines(1)
        .fontColor($r("sys.color.font_primary"))
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(100)
    }
    .width('100%')
    .height('100%')
    .padding({left: 13, right: 13})
    .alignItems(VerticalAlign.Center)
    .justifyContent(FlexAlign.Start)
  }
}