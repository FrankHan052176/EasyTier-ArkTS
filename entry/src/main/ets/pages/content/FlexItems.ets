import Manager from "../../Manager"
import { cidr, Config, exit_node, listener, network_identity, peer, route,
  SharedPeer,
  WrappedString } from "../../util/config/ETConfig"
import { ItemBuilder } from "../../util/ItemBuilders"
import { SafeLightWeightSet } from "../../util/SafeLightWeightSet"
import { LengthMetrics, SymbolGlyphModifier } from "@kit.ArkUI"
import { ItemEditSheet } from "../../util/ItemEditSheet"
import { ToolButton } from "../Components"
import EventHelper from "../../util/EventHelper"
import Logger from "../../util/Logger"
import { PeerRoutePair } from "../../util/info/PeerInfo"

export enum ItemSize {
  SMALL,NORMAL,BIG
}
export type itemType = peer | network_identity | cidr | listener | route | exit_node | WrappedString | ResourceStr | Config | PeerRoutePair | SharedPeer
function newItemFunc(items: SafeLightWeightSet<itemType>): itemType {
  return items.typeConstructor()
}
function copyItemFunc(item: itemType): itemType {
  if (item instanceof peer) {
    return new peer().from(item)
  }else if (item instanceof network_identity) {
    return new network_identity().from(item)
  }else if (item instanceof cidr) {
    return new cidr().from(item)
  }else if (item instanceof listener) {
    return new listener().from(item)
  }else if (item instanceof route) {
    return new route().from(item)
  }else if (item instanceof exit_node) {
    return new exit_node().from(item)
  }else if (item instanceof WrappedString) {
    return new WrappedString().from(item)
  }else return new WrappedString()
}
function deleteItemFunc(item: itemType) {
  if (item instanceof peer) {
    Manager.peers.delete(item)
  }else if (item instanceof network_identity) {
    Manager.network_identities.delete(item)
  }else if (item instanceof cidr) {
    Manager.cidrs.delete(item)
  }else if (item instanceof listener) {
    Manager.listeners.delete(item)
  }else if (item instanceof route) {
    Manager.routes.delete(item)
  }else if (item instanceof exit_node) {
    Manager.exit_nodes.delete(item)
  }else if (item instanceof WrappedString) {
    Manager.whitelist.delete(item)
  }
}
function isEditable(item: itemType): boolean {
  if (item instanceof SharedPeer) {
    return !Manager.sharedPeers.has(item)
  }else return true
}
@ComponentV2
export struct FlexItems {
  @Param @Require config: Config
  @Param @Require type: string
  @Param @Require items: SafeLightWeightSet<itemType>
  @Param @Require comp_width: number
  @Param @Require clickCallback: (item: itemType) => void
  @Param @Require selectedFunc: (item: itemType) => boolean
  @Local sheet: boolean = false;
  @Local add: boolean = false;
  @Local newItem: itemType | undefined
  @Local oldItem: itemType | undefined

  @Builder
  ItemMenu(item: itemType) {
    Menu() {
      if (isEditable(item)) {
        MenuItem({ symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.pencil_and_card')).fontSize('24vp'), content: "编辑" })
          .onClick(() => {
            animateToImmediately({ curve: Curve.EaseIn, duration: 150 }, () => {
              this.newItem = copyItemFunc(item)
              this.oldItem = copyItemFunc(item)
              this.sheet = true
            })
          })
      }
      MenuItem({ symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.trash')).fontColor([$r("sys.color.warning")]).fontSize('24vp'), content: "删除" })
        .onClick(() => {
          animateToImmediately({ curve: Curve.EaseIn, duration: 150 }, () => {
            deleteItemFunc(item)
          })
        })
    }
  }

  aboutToAppear(): void {
    EventHelper.emitterListener(this.type+"_add",() => {
      Logger.info("receive "+this.type+"_add")
      this.newItem = newItemFunc(this.items)
      this.add = true
    })
  }

  @Builder
  SheetTitle(edit: boolean = false) {
    Row() {
      Row() {
        Text(edit?$r("app.string.i18_edit"):$r("app.string.i18_add"))
          .fontColor($r("sys.color.font_primary"))
          .fontSize(20)
        Text($r("app.string.i18_type_"+this.type))
          .fontColor($r("sys.color.font_primary"))
          .fontSize(20)
      }
      ToolButton({
        symbol: $r("sys.symbol.checkmark"),
        bgColor: $r("sys.color.comp_background_emphasize"),
        symbolColor: [$r("sys.color.font_on_primary")]
      })
        .onClick(() => {
          if (this.sheet) {
            this.items.delete(this.oldItem!)
            this.items.add(this.newItem!)
          }else {
            this.items.add(this.newItem!)
          }
          this.newItem = undefined
          this.oldItem = undefined
          this.sheet = false
          this.add = false
        })
    }
    .alignItems(VerticalAlign.Center)
    .justifyContent(FlexAlign.SpaceBetween)
    .width('100%')
  }

  build() {
    Column() {
      Row() {
        Text($r("app.string.i18_type_"+this.type))
          .fontSize(17)
          .fontColor($r("sys.color.font_primary"))
        Row() {
          Text("新增")
            .fontSize(17)
            .fontColor($r("sys.color.font_primary"))
          Text() {
            SymbolSpan($r("sys.symbol.plus"))
              .fontSize(17)
              .fontColor([$r("sys.color.font_primary")])
          }
        }
        .onClick(() => {
          EventHelper.emitterPublish(this.type+"_add")
        })
      }
      .alignItems(VerticalAlign.Center)
      .justifyContent(FlexAlign.SpaceBetween)
      .width('100%')
      .padding({left: 5, bottom: this.items.size > 0?10:5, right: 5})
      Flex({space: {
        main: LengthMetrics.vp(10), cross: LengthMetrics.vp(10)
      },wrap: FlexWrap.Wrap}) {
        LazyForEach(this.items, (item: itemType) => {
          ItemBuilder({item: item, isSelected: this.selectedFunc(item), itemWidth: (this.comp_width-30)/2})
            .onClick(() => {
              this.clickCallback(copyItemFunc(item))
            })
            .bindContextMenu(this.ItemMenu(item), ResponseType.RightClick)
            .bindContextMenu(this.ItemMenu(item), ResponseType.LongPress)
        }, (item: itemType) => {return "index"+this.config.instance_id+"_"+this.type+"_"+item.toString()})
      }
      .width('100%')
      .bindSheet($$this.add, ItemEditSheet(this.newItem!), {
        height: SheetSize.FIT_CONTENT,
        preferType: SheetType.CENTER,
        showClose: false,
        dragBar: false,
        blurStyle: BlurStyle.Thin,
        title: this.SheetTitle(),
        onWillDisappear: () => {
          this.newItem = undefined
          this.oldItem = undefined
        }
      })
    }
    .animation({
      duration: 300,
      curve: Curve.Rhythm
    })
    .bindSheet($$this.sheet, ItemEditSheet(this.newItem!), {
      height: SheetSize.FIT_CONTENT,
      preferType: SheetType.BOTTOM,
      showClose: false,
      dragBar: false,
      blurStyle: BlurStyle.Thin,
      title: this.SheetTitle(true),
      onWillDisappear: () => {
        this.newItem = undefined
        this.oldItem = undefined
      }
    })
    .width(this.comp_width)
    .alignItems(HorizontalAlign.Center)
    .borderRadius(18)
    .backgroundColor($r("sys.color.comp_background_primary"))
    .padding({top: 15, left: 10, right: 10, bottom: 10})
    .clip(true)
  }
}