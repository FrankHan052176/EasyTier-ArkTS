import { AppManager } from "../../../AppManager";
import { deleteFieldValue, FieldValue } from "../../../class/config/Basic";
import { FieldValueDataSource } from "../../../class/FieldValueDataSource";
import { NetworkConfig } from "../../../protobuf/api_manage";
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

@ComponentV2
export struct ListField {
  @Param @Require config: NetworkConfig;
  @Param @Require field: string;
  @Param @Require type: string;
  @Local dataSource: FieldValueDataSource = AppManager.data.getDataSource(this.type)
  @Local item_height: number = 0
  private scroller: ListScroller = new ListScroller();

  @Computed
  get comp_height() {
    if (this.dataSource.totalCount() == 0) {
      return 70
    }else if (this.dataSource.totalCount() <= 2) {
      return this.dataSource.totalCount()*this.item_height+(this.dataSource.totalCount()-1)*10
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
              // TODO 端口转发
              break;
            }
          }
          EventHelper.emitterPublish("edit_open_sheet",{
            data: {
              type: "edit_"+this.type+"_"+this.field
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
          deleteFieldValue(this.config, this.type, this.field, value)
        })
    }
  }

  build() {
    List({space: 10, scroller: this.scroller}) {
      if (this.dataSource.totalCount() > 0) {
        LazyForEach(this.dataSource, (item: FieldValue) => {
          ListItem() {
            ListFieldValue({config: this.config, field: this.field, type: this.type, item: item})
              .width('100%')
              .onAreaChange((a,b) => {
                this.item_height = b.height.valueOf() as number
              })
          }
          .swipeAction({
            end: this.rightButton(item)
          })
        })
      }else {
        ListItem() {
          Column() {
            Row() {
              SymbolGlyph($r("sys.symbol.minus_circle"))
                .margin({right: 8})
              Text(getFieldI18Name(this.field))
              Text("为空")
            }
          }
          .alignItems(HorizontalAlign.Center)
          .justifyContent(FlexAlign.Center)
          .height(this.comp_height)
          .width('100%')
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