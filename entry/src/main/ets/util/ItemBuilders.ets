import Manager from "../Manager";
import { ToolButton } from "../pages/Components";
import { itemType } from "../pages/content/FlexItems";
import { cidr,
  Config,
  exit_node, listener, network_identity, peer,
  Protocol,
  protocolColor, route,
  SharedPeer,
  WrappedString } from "./config/ETConfig";
import { convertAddrToIp, safePassword, vp2fp } from "./Conversion";
import { PeerRoutePair } from "./info/PeerInfo";
import Logger from "./Logger";

function getObj(item: itemType): object {
  return item as object
}

@ComponentV2
export struct ItemBuilder {
  @Param @Require item: itemType;
  @Param @Require isSelected: boolean
  @Param @Require itemWidth: Length
  @Param itemHeight: number = 80
  @Param switchHighlight: boolean = true
  @Param shadowRadius: number = 30
  @BuilderParam config_buttons: (config:Config)=>void = this.StartButton
  @Local isHighlight: boolean = false
  @Local highlightPos: [number, number] = [-999, -999]
  @Local realWidth: number = 0

  @Builder
  StartButton(item: Config) {
    ToolButton({
      buttonSize: this.itemHeight-16,
      symbol: Manager.info_uuid == item.instance_id ? $r("sys.symbol.pause") : $r("sys.symbol.play_fill"),
      symbolColor: [$r("sys.color.font_primary")]
    })
      .onClick(() => {
        Manager.changeInstanceStatus(this.item as Config)
      })
      .width(this.itemHeight-16).height(this.itemHeight-16)
  }

  build() {
    Stack({alignContent: Alignment.Center}) {
      Column() {
        if (this.item instanceof peer) {
          PeerBuilder({item: this.item, comp_width: this.realWidth, comp_height: this.itemHeight})
        }else if (this.item instanceof network_identity) {
          ProfileBuilder({item: this.item})
        }else if (this.item instanceof cidr) {
          CidrBuilder({item: this.item})
        }else if (this.item instanceof listener) {
          ListenerBuilder({item: this.item})
        }else if (this.item instanceof WrappedString) {
          WhiteListBuilder({item: this.item})
        }else if (this.item instanceof route) {
          RouteBuilder({item: this.item})
        }else if (this.item instanceof exit_node) {
          ExitNodeBuilder({item: this.item})
        }else if (this.item instanceof Config) {
          Row() {
            Column() {
              Text(this.item.instance_name)
                .maxLines(1)
                .width('80%')
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .fontSize(vp2fp((this.itemHeight-18)/2.5))
                .fontColor($r("sys.color.font_primary"))
              Text(this.item.instance_id)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .width('80%')
                .fontSize(vp2fp((this.itemHeight-18)/5))
                .fontColor($r("sys.color.font_secondary"))
                .margin({top: 2})
            }
            .alignItems(HorizontalAlign.Start)
            .justifyContent(FlexAlign.Center)
            .layoutWeight(100)
            this.config_buttons(this.item)
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)
          .justifyContent(FlexAlign.SpaceBetween)
          .padding({
            top: 8,
            bottom: 8,
            left: 12,
            right: 12
          })
        }else if (getObj(this.item)["bundleName"] != undefined) {
          Text(this.item as ResourceStr)
            .fontSize(12)
            .textOverflow({ overflow: TextOverflow.MARQUEE })
            .fontColor($r("sys.color.font_primary"))
        }else if (getObj(this.item)["route"] != undefined) {
          RemotePeerBuilder(this.item as PeerRoutePair)
        }else if (this.item == "unselected") {
          Text("请点击需要启动的实例")
            .fontSize(14)
            .fontColor($r("sys.color.font_primary"))
        }
      }
      .zIndex(3)
      .width('100%')
      .height('100%')
      .backgroundColor(Color.Transparent)
      .alignItems(HorizontalAlign.Center)
      .justifyContent(FlexAlign.Center)
      .onMouse((event) => {
        if (!this.switchHighlight) {
          return;
        }
        if (event.action == MouseAction.Press) {
          this.highlightPos = [event.x, event.y]
          this.isHighlight = true
        }else if (event.action == MouseAction.CANCEL || event.action == MouseAction.Release) {
          this.highlightPos = [-999, -999]
          this.isHighlight = false
        }
      })
      .onTouch((event) => {
        if (!this.switchHighlight) {
          return;
        }
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
          .borderRadius(this.itemHeight/20*3)
          .backgroundColor(Color.Transparent)
          .radialGradient({
            center: this.highlightPos,
            radius: this.realWidth/3,
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
            duration: 300,
            curve: Curve.Ease
          }))
      }else {
        Column()
          .zIndex(1)
          .width('100%')
          .height('100%')
          .backgroundColor(this.isSelected?$r("app.color.selected_background"):$r("app.color.normal_background"))
          .transition(TransitionEffect.OPACITY.animation({
            duration: 300,
            curve: Curve.Ease
          }))
      }
    }
    .onAreaChange((a,b) => {
      this.realWidth = b.width as number
    })
    .width(this.itemWidth)
    .height(this.itemHeight)
    .border({
      width: 1,
      color: this.isSelected?$r("app.color.selected_border"):$r("sys.color.background_fourth"),
      radius: this.itemHeight/20*3
    })
    .shadow(this.isSelected?{
      radius: this.isHighlight?2:this.shadowRadius,
      color: $r("app.color.selected_shadow")
    }:{
      radius: this.isHighlight?2:this.shadowRadius,
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
    .padding({top: 15, bottom: 15})
    .alignItems(HorizontalAlign.Center)
    .justifyContent(FlexAlign.SpaceBetween)
    .width('100%')
    .height('100%')
  }
}

@ComponentV2
export struct PeerBuilder {
  @Param @Require item: peer
  @Param @Require comp_height: number
  @Param @Require comp_width: number

  isSharedPeer(): boolean {
    if (this.item instanceof SharedPeer) {
      return true
    }else {
      return false
    }
  }

  isAllowRelay(): boolean {
    if (this.item instanceof SharedPeer) {
      return this.item.allow_relay
    }else {
      return false
    }
  }

  getPeerText(): string {
    if (this.item instanceof SharedPeer) {
      return this.item.name
    }else {
      return this.item._domain
    }
  }

  @Computed
  get padding_3() {
    return this.comp_height/80*2.5
  }

  @Computed
  get padding_5() {
    return this.comp_height/18
  }

  @Computed
  get border_radius_8() {
    return this.comp_height/10
  }

  @Computed
  get font_size_12() {
    return this.comp_height/20*3
  }

  @Computed
  get font_size_14() {
    return this.comp_height/40*8
  }

  build() {
    Stack({alignContent: Alignment.TopStart}) {
      Row() {
        Row() {
          if (this.isSharedPeer()) {
            Text(this.isAllowRelay()?"可转发":"禁转发")
              .fontColor($r("sys.color.font_on_primary"))
              .fontSize(vp2fp(this.font_size_12))
              .width(this.font_size_12*4)
              .borderRadius(this.border_radius_8)
              .backgroundColor(this.isAllowRelay()?$r("sys.color.confirm"):$r("sys.color.warning"))
              .padding({top: this.padding_3, bottom: this.padding_3, right: this.padding_5, left: this.padding_5})
              .textAlign(TextAlign.Center)
              .margin({right: this.padding_5})
          }
          Text(this.item._protocol.toUpperCase())
            .fontColor($r("sys.color.font_on_primary"))
            .fontSize(vp2fp(this.font_size_12))
            .width(this.font_size_12*4)
            .borderRadius(this.border_radius_8)
            .backgroundColor(protocolColor(this.item._protocol))
            .padding({top: this.padding_3, bottom: this.padding_3, right: this.padding_5, left: this.padding_5})
            .textAlign(TextAlign.Center)
        }
        Row() {
          if (!this.isSharedPeer()) {
            Text() {
              SymbolSpan($r('sys.symbol.position'))
                .fontColor([$r("sys.color.font_primary")])
                .fontSize(vp2fp(this.font_size_14))
            }
            Text(this.item._port.toString())
              .fontColor($r("sys.color.font_primary"))
              .fontSize(vp2fp(this.font_size_14))
              .padding({top: this.padding_3, bottom: this.padding_3, right: this.padding_5, left: this.padding_5})
              .textAlign(TextAlign.Center)
          }
        }
      }
      .alignItems(VerticalAlign.Top)
      .justifyContent(FlexAlign.SpaceBetween)
      .width('100%')
      .padding({top: this.padding_5, left: this.padding_5, right: this.padding_5})
      Row() {
        Row() {
          Text() {
            SymbolSpan($r('sys.symbol.worldclock'))
              .fontColor([$r("sys.color.font_primary")])
              .fontSize(vp2fp(this.font_size_14))
          }
          .margin({right: this.padding_5})
          Text(this.getPeerText())
            .maxLines(1)
            .fontSize(vp2fp(this.font_size_14))
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
  @Param @Require item: WrappedString

  build() {
    Row() {
      Text() {
        SymbolSpan($r('sys.symbol.person'))
          .fontColor([$r("sys.color.font_primary")])
      }
      .margin({right: 5})
      Text(this.item.value)
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

function getProtocol(value: PeerRoutePair): Protocol[] {
  let arr = new Array<Protocol>()
  if (value.peer) {
    value.peer.conns.forEach((conn) => {
      if (conn.tunnel) {
        arr.push(conn.tunnel.tunnel_type as Protocol)
      }
    })
  }
  return arr
}

function getRouteCost(value: PeerRoutePair): string {
  if (value.route) {
    const cost = value.route.cost
    return cost ? cost === 1 ? 'p2p' : `relay(${cost})` : "local"
  }else {
    return "?"
  }
}

@Builder
export function RemotePeerBuilder(value: PeerRoutePair) {
  Stack({alignContent: Alignment.TopStart}) {
    Row() {
      ForEach(getProtocol(value), (item: Protocol) => {
        Text(item.toUpperCase())
          .fontColor($r("sys.color.font_on_primary"))
          .fontSize(12)
          .borderRadius(6)
          .backgroundColor(protocolColor(item))
          .padding({top: 3, bottom: 3, right: 5, left: 5})
          .textAlign(TextAlign.Center)
          .margin({left: 5})
      })
    }
    .alignItems(VerticalAlign.Center)
    .justifyContent(FlexAlign.End)
    .width('100%')
    .margin({bottom: 10})
    .offset({
      x: -3,
      y: 3
    })
    Row() {
      Text(getRouteCost(value))
        .fontColor($r("sys.color.font_on_primary"))
        .fontSize(12)
        .borderRadius(6)
        .backgroundColor($r("sys.color.comp_background_emphasize"))
        .padding({top: 3, bottom: 3, right: 5, left: 5})
        .textAlign(TextAlign.Center)
    }
    .alignItems(VerticalAlign.Center)
    .justifyContent(FlexAlign.Start)
    .width('100%')
    .margin({bottom: 10})
    .offset({
      x: 3,
      y: 3
    })
    Column() {
      Text(value.route.hostname)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .fontSize(14)
        .fontColor($r("sys.color.font_primary"))
        .textAlign(TextAlign.Center)
        .padding({left: 10, right: 10})
      Text(value.route.ipv4_addr?convertAddrToIp(value.route.ipv4_addr?.address.addr):"")
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .fontSize(14)
        .fontColor($r("sys.color.font_primary"))
        .textAlign(TextAlign.Center)
        .padding({left: 10, right: 10})
    }
    .height('100%')
    .width('100%')
    .alignItems(HorizontalAlign.Center)
    .justifyContent(FlexAlign.Center)
  }
}

@Builder
export function ConfigBuilder(config: Config, height: number, showButton: boolean) {

}