import { AppManager } from "../../../AppManager";
import { deleteFieldValue, FieldValue } from "../../../class/config/Basic";
import { FieldValueDataSource } from "../../../class/FieldValueDataSource";
import { lane } from "../../../util/Conversion";
import { ToolButton } from "../../util/ToolButtons";
import { getFieldI18Name } from "../FieldEdit";
import { ListFieldValue } from "../ListFieldValue";
import { LengthMetrics } from "@kit.ArkUI";
import { Cidr, setEditValue_Cidr } from "../../../class/config/Cidr";
import { setEditValue_Url, Url } from "../../../class/config/Url";
import { IP, setEditValue_IP } from "../../../class/config/IP";
import { NetworkName, setEditValue_NetworkName } from "../../../class/config/NetworkName";
import { EventHelper } from "../../../util/EventHelper";
import { PortForward, setEditValue_PortForward } from "../../../class/config/PortForward";
import { PortForwardConfig } from "../../../protobuf/api_manage";
import { Logger } from "../../../util/Logger";

@ComponentV2
export struct ListField {
  @Param @Require field: string;
  @Param @Require type: string;
  @Local dataSource: FieldValueDataSource = AppManager.data.getDataSource(this.type)
  @Local items: (FieldValue | undefined)[] = []
  @Local item_height: number = 0
  private scroller: ListScroller = new ListScroller();

  @Computed
  get config() {
    return AppManager.data.configUUIDMap.get(AppManager.data.editingInstance ?? "")
  }

  @Computed
  get preference() {
    return AppManager.preference.configPreferences.get(AppManager.data.editingInstance ?? "")
  }

  updateItems() {
    this.items = AppManager.data.configUUIDMap.get(AppManager.data.editingInstance ?? "")![this.field].map((value: string | PortForwardConfig) => {
      switch (this.type) {
        case "cidr": return new Cidr().readFrom(value as string)?.bind(this.field)
        case "route": return new Cidr().readFrom(value as string)?.bind(this.field)
        case "peer": return new Url().readFrom(value as string)?.bind(this.field)
        case "mappedListener":
        case "listener": return new Url().readFrom(value as string)?.bind(this.field)
        case "ip": return new IP().readFrom(value as string)?.bind(this.field)
        case "string": return new NetworkName().readFrom(value as string)?.bind(this.field)
        case "port_forward": return new PortForward().readFrom(value as PortForwardConfig)?.bind(this.field)
        default: return undefined
      }
    })
  }

  aboutToAppear(): void {
    if (!this.config![this.field]) {
      if (this.type === "port_forward") {
        this.config![this.field] = new Array<PortForwardConfig>()
      }else {
        this.config![this.field] = new Array<string>()
      }
    }
    this.updateItems()
    EventHelper.emitterListener("edit_refresh_"+this.field, () => {
      this.updateItems()
      this.preference?.putSync(this.field, this.config![this.field])
      this.preference?.flushSync()
    })
  }

  @Computed
  get comp_height() {
    if (this.items.length == 0) {
      return 70
    }else if (this.items.length <= 2) {
      return this.items.length*this.item_height+(this.items.length-1)*10
    }else {
      return 2.5*this.item_height+10
    }
  }

  @Builder
  rightButton(value: FieldValue) {
    Row() {
      ToolButton({symbol: $r("sys.symbol.square_and_pencil"), buttonSize: (lane(1)-20)/3-10, bgColor: $r("sys.color.comp_background_primary")})
        .margin({
          left: 10
        })
        .onClick(() => {
          this.scroller.closeAllSwipeActions()
          switch (this.type) {
            case "route":
            case "cidr": {
              setEditValue_Cidr(value as Cidr)
              break;
            }
            case "mappedListener":
            case "listener":
            case "peer": {
              setEditValue_Url(value as Url)
              break;
            }
            case "ip": {
              setEditValue_IP(value as IP)
              break;
            }
            case "string": {
              setEditValue_NetworkName(value as NetworkName)
              break;
            }
            case "port_forward": {
              setEditValue_PortForward(value as PortForward)
              break;
            }
          }
          EventHelper.emitterPublish("edit_open_sheet",{
            data: {
              type: "edit_"+this.type+"|"+this.field
            }
          })
        })
      ToolButton({symbol: $r("sys.symbol.trash"), buttonSize: (lane(1)-20)/3-10, bgColor: $r("sys.color.comp_background_primary"), symbolColor: [$r("sys.color.warning")]})
        .margin({
          left: 10,
          right: 10
        })
        .onClick(() => {
          this.scroller.closeAllSwipeActions()
          deleteFieldValue(this.config!, this.type, this.field, value)
          this.updateItems()
        })
    }
  }

  build() {
    List({space: 10, scroller: this.scroller}) {
      if (this.items.length > 0) {
        ForEach(this.items, (item: FieldValue | undefined) => {
          if (item) {
            ListItem() {
              ListFieldValue({field: this.field, type: this.type, value: item})
                .width('100%')
                .onAreaChange((a,b) => {
                  this.item_height = b.height.valueOf() as number
                })
            }
            .swipeAction({
              end: this.rightButton(item)
            })
          }
        })
      }else {
        ListItem() {
          Column() {
            Row() {
              SymbolGlyph($r("sys.symbol.minus_circle"))
                .margin({right: 8})
                .fontColor([$r("sys.color.font_primary")])
              Text(getFieldI18Name(this.field))
              Text("为空")
            }
          }
          .alignItems(HorizontalAlign.Center)
          .justifyContent(FlexAlign.Center)
          .height(this.comp_height)
          .width('100%')
          .borderRadius(18)
          .backgroundColor($r("sys.color.comp_background_primary"))
        }
      }
    }
    .scrollBar(BarState.Off)
    .fadingEdge(true, {
      fadingEdgeLength: LengthMetrics.vp(8)
    })
    .height(this.comp_height)
    .width('100%')
  }
}