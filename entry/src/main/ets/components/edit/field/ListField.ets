import { AppManager } from '../../../AppManager';
import { deleteFieldValue as deleteListValue, FieldValue, setEditOriginalValue } from '../../../class/config/Basic';
import { FieldValueDataSource } from '../../../class/FieldValueDataSource';
import { lane } from '../../../util/Conversion';
import { ToolButton } from '../../util/ToolButtons';
import { getFieldI18Name } from '../FieldEdit';
import { ListFieldValue } from '../ListFieldValue';
import { LengthMetrics } from '@kit.ArkUI';
import { Cidr, setEditValue_Cidr } from '../../../class/config/Cidr';
import { setEditValue_Url, Url } from '../../../class/config/Url';
import { IP, setEditValue_IP } from '../../../class/config/IP';
import { NetworkName, setEditValue_NetworkName } from '../../../class/config/NetworkName';
import { EventHelper } from '../../../util/EventHelper';
import { PortForward, setEditValue_PortForward } from '../../../class/config/PortForward';
import { getFieldPathValue, syncTopLevelField } from '../../../ConfigSyncUtil';
import { ConfigFieldValue } from '../../../config/schema/SchemaConfig';
import { Logger } from '../../../shared/logging/Logger';
import { getEditingConfigFieldRefreshEvent } from '../../../services/config/storage/StoredConfigService';

@ComponentV2
export struct ListField {
  @Param @Require field: string;
  @Param @Require type: string;
  @Local dataSource: FieldValueDataSource = AppManager.data.getDataSource(this.type)
  @Local items: (FieldValue | undefined)[] = []
  @Local item_height: number = 0
  private scroller: ListScroller = new ListScroller();
  private fieldRefreshEvent: string = ''
  private editRefreshEvent: string = ''
  private fieldRefreshCallback = () => {
    this.updateItems()
  }

  @Computed
  get config() {
    return AppManager.easytier.getEditingConfig()
  }

  @Computed
  get comp_height() {
    if (this.items.length == 0) {
      return 70
    } else if (this.items.length <= 2) {
      return this.items.length * this.item_height + (this.items.length - 1) * 10
    } else {
      return 2.5 * this.item_height + 10
    }
  }

  updateItems() {
    const rawValues: ConfigFieldValue = getFieldPathValue(AppManager.easytier.getEditingConfig()!, [this.field])
    const values: (string | ESObject)[] = rawValues as (string | ESObject)[]
    this.items = values.map((value: string | ESObject) => {
      switch (this.type) {
        case "cidr":
          return new Cidr().readFrom(value as string)?.bind(this.field)
        case "route":
          return new Cidr().readFrom(value as string)?.bind(this.field)
        case "peer":
          return new Url().readFrom(value as string)?.bind(this.field)
        case "mapped_listener":
        case "listener":
          return new Url().readFrom(value as string)?.bind(this.field)
        case "ip":
          return new IP().readFrom(value as string)?.bind(this.field)
        case "network_name":
          return new NetworkName().readFrom(value as string)?.bind(this.field)
        case "port_forward":
          return new PortForward().readFrom(value as ESObject)?.bind(this.field)
        default:
          return undefined
      }
    })
  }

  aboutToAppear(): void {
    if (!this.config![this.field]) {
      if (this.type === "port_forward") {
          this.config![this.field] = new Array<ESObject>()
      } else {
        this.config![this.field] = new Array<string>()
      }
    }
    this.updateItems()
    this.fieldRefreshEvent = getEditingConfigFieldRefreshEvent(this.field)
    this.editRefreshEvent = "edit_refresh_" + this.field
    EventHelper.emitterListener(this.fieldRefreshEvent, this.fieldRefreshCallback)
    EventHelper.emitterListener(this.editRefreshEvent, this.fieldRefreshCallback)
  }

  aboutToDisappear(): void {
    if (this.fieldRefreshEvent.length > 0) {
      EventHelper.emitterOff(this.fieldRefreshEvent, this.fieldRefreshCallback)
      this.fieldRefreshEvent = ''
    }
    if (this.editRefreshEvent.length > 0) {
      EventHelper.emitterOff(this.editRefreshEvent, this.fieldRefreshCallback)
      this.editRefreshEvent = ''
    }
  }

  @Builder
  rightButton(value: FieldValue) {
    Row() {
      ToolButton({
        symbol: $r("sys.symbol.square_and_pencil"),
        buttonSize: (lane(1) - 20) / 3 - 10,
        bgColor: $r("sys.color.comp_background_primary")
      })
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
            case "mapped_listener":
            case "listener":
            case "peer": {
              setEditValue_Url(value as Url)
              break;
            }
            case "ip": {
              setEditValue_IP(value as IP)
              break;
            }
            case "network_name": {
              setEditValue_NetworkName(value as NetworkName)
              break;
            }
            case "port_forward": {
              setEditValue_PortForward(value as PortForward)
              break;
            }
          }
          setEditOriginalValue(this.type, value)
          Logger.debug(`ListField edit open field=${this.field} type=${this.type} original=${value.toString()}`, 'ListField')
          EventHelper.emitterPublish("edit_open_sheet", {
            data: {
              type: "edit_" + this.type + "|" + this.field
            }
          })
        })
      ToolButton({
        symbol: $r("sys.symbol.trash"),
        buttonSize: (lane(1) - 20) / 3 - 10,
        bgColor: $r("sys.color.comp_background_primary"),
        symbolColor: [$r("sys.color.warning")]
      })
        .margin({
          left: 10,
          right: 10
        })
        .onClick(() => {
          this.scroller.closeAllSwipeActions()
          Logger.debug(`ListField delete field=${this.field} type=${this.type} value=${value.toString()}`, 'ListField')
          deleteListValue(this.config!, this.type, this.field, value)
          this.updateItems()
          syncTopLevelField(this.config!.instance_id!, this.field, this.config!)
        })
    }
  }

  build() {
    List({ space: 10, scroller: this.scroller }) {
      if (this.items.length > 0) {
        ForEach(this.items, (item: FieldValue | undefined) => {
          if (item) {
            ListItem() {
              ListFieldValue({ field: this.field, type: this.type, value: item })
                .width('100%')
                .onAreaChange((a, b) => {
                  this.item_height = b.height.valueOf() as number
                })
            }
            .swipeAction({
              end: this.rightButton(item)
            })
          }
        })
      } else {
        ListItem() {
          Column() {
            Row() {
              SymbolGlyph($r("sys.symbol.minus_circle"))
                .margin({ right: 8 })
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
