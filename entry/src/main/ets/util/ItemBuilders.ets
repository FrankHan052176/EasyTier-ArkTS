import Manager from "../Manager";
import { ToolButton } from "../pages/Components";
import { itemType } from "../pages/content/FlexItems";
import { cidr,
  Config,
  exit_node, listener, network_identity, peer, protocolColor, route,
  WrappedString } from "./config/ETConfig";
import { safePassword } from "./Conversion";
import Logger from "./Logger";
import { requestLocPerm } from "./Permission";

@ComponentV2
export struct ItemBuilder {
  @Param @Require item: itemType
  @Param @Require isSelected: boolean
  @Param @Require itemWidth: Length
  @Param itemHeight: number = 80
  @Param switchHighlight: boolean = true
  @Param shadowRadius: number = 30
  @Local isHighlight: boolean = false
  @Local highlightPos: [number, number] = [-999, -999]
  @Local realWidth: number = 0

  build() {
    Stack({alignContent: Alignment.Center}) {
      Column() {
        if (this.item instanceof peer) {
          PeerBuilder({item: this.item})
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
                .fontSize(18)
                .fontColor($r("sys.color.font_primary"))
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .height(18)
              Text(this.item.instance_id)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .width('30%')
                .fontSize(10)
                .fontColor($r("sys.color.font_secondary"))
                .height(14)
                .align(Alignment.Bottom)
            }
            .alignItems(HorizontalAlign.Start)
            .justifyContent(FlexAlign.Center)
            ToolButton({
              symbol: Manager.infos.has(this.item.instance_id)?$r("sys.symbol.pause"):$r("sys.symbol.play_fill"),
              symbolColor: [$r("sys.color.font_primary")]
            })
              .onClick(() => {
                if (Manager.infos.has((this.item as Config).instance_id)) {
                  if (!Manager.stopInstance(this.item as Config)) {
                    Logger.error("关闭网络失败")
                  }
                }else {
                  if (Manager.infos.size > 0) {
                    this.getUIContext().getPromptAction().showToast({
                      message: "请先关闭正在运行的网络"
                    })
                  }else {
                    requestLocPerm(this.getUIContext().getHostContext()!).then((value) => {
                      if (!value) {
                        this.getUIContext().getPromptAction().showToast({
                          message: "拒绝授权定位权限将无法进行后台保活"
                        })
                      }
                      Manager.startInstance(this.item as Config)
                    })
                  }
                }
              })
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)
          .justifyContent(FlexAlign.SpaceBetween)
          .padding({top: 8, bottom: 8, left: 12, right: 12})
        }else {
          Text(this.item)
            .fontSize(12)
            .textOverflow({ overflow: TextOverflow.MARQUEE })
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
          .borderRadius(12)
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
    .onAreaChange((a,b) => {
      this.realWidth = b.width as number
    })
    .width(this.itemWidth)
    .height(this.itemHeight)
    .border({
      width: 1,
      color: this.isSelected?$r("app.color.selected_border"):$r("sys.color.background_fourth"),
      radius: 12
    })
    .shadow(this.isSelected?{
      radius: this.shadowRadius,
      color: $r("app.color.selected_shadow")
    }:{
      radius: this.shadowRadius,
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