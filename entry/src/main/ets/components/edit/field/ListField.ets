import { AppManager } from '../../../AppManager';
import { deleteFieldValue as deleteListValue, FieldValue, setEditOriginalValue } from '../../../class/config/Basic';
import { lane } from '../../../util/Conversion';
import { ToolButton } from '../../util/ToolButtons';
import { getFieldI18Name } from '../FieldLabel';
import { ListFieldItemModel, ListFieldValue } from '../ListFieldValue';
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

interface PortForwardRawValue {
  bind_ip: string
  bind_port: number | string
  dst_ip: string
  dst_port: number | string
  proto: string
}

type ListRawValue = string | PortForwardRawValue

@ComponentV2
export struct ListField {
  @Param @Require field: string;
  @Param @Require type: string;
  @Local items: ListFieldItemModel[] = []
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

  private stringifyRawValue(value: ListRawValue): string {
    if (typeof value === 'string') {
      return value
    }
    try {
      return JSON.stringify(value)
    } catch (_) {
      return `${value}`
    }
  }

  private buildFieldValue(value: ListRawValue | undefined): FieldValue | undefined {
    if (value === undefined) {
      return undefined
    }
    switch (this.type) {
      case "cidr":
      case "route":
        return new Cidr().readFrom(value as string)?.bind(this.field)
      case "peer":
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
  }

  private createDisplayItem(value: ListRawValue, index: number): ListFieldItemModel {
    const rawText = this.stringifyRawValue(value)
    const fieldValue = this.buildFieldValue(value)
    const item: ListFieldItemModel = {
      key: `${this.field}:${index}:${rawText}`,
      index: index,
      type: this.type,
      rawText: rawText,
      title: rawText,
      subtitle: '',
      protocol: undefined,
      valid: fieldValue !== undefined
    }
    if (!fieldValue) {
      return item
    }
    switch (this.type) {
      case "peer":
      case "mapped_listener":
      case "listener": {
        const url = fieldValue as Url
        item.title = url.domain
        item.subtitle = url.port.length > 0 ? url.port : (this.type === "listener" || this.type === "mapped_listener" ? "默认端口" : "")
        item.protocol = url.proto
        break
      }
      case "port_forward": {
        const portForward = fieldValue as PortForward
        item.title = `${portForward.to}:${portForward.to_port}`
        item.subtitle = `${portForward.from}:${portForward.from_port}`
        item.protocol = portForward.proto
        break
      }
      default:
        item.title = fieldValue.toString()
        break
    }
    return item
  }

  private currentRawValues(): ListRawValue[] | undefined {
    const rawValues: ConfigFieldValue = getFieldPathValue(AppManager.easytier.getEditingConfig()!, [this.field])
    if (!Array.isArray(rawValues)) {
      return undefined
    }
    if (this.type === "port_forward") {
      return rawValues as PortForwardRawValue[]
    }
    return rawValues as string[]
  }

  private updateItems() {
    const rawValues: ListRawValue[] | undefined = this.currentRawValues()
    if (!rawValues) {
      this.items = []
      return
    }
    this.items = rawValues.map((value: ListRawValue, index: number) => {
      return this.createDisplayItem(value, index)
    })
  }

  aboutToAppear(): void {
    if (!this.config![this.field]) {
      if (this.type === "port_forward") {
          this.config![this.field] = new Array<PortForwardRawValue>()
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
    this.scroller.closeAllSwipeActions()
    this.items = []
    this.item_height = 0
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
  rightButton(item: ListFieldItemModel) {
    Row() {
      if (item.valid) {
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
            const values: ListRawValue[] | undefined = this.currentRawValues()
            if (!values) {
              return
            }
            const value: FieldValue | undefined = this.buildFieldValue(values[item.index])
            if (!value) {
              return
            }
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
      }
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
          const values: ListRawValue[] | undefined = this.currentRawValues()
          if (!values) {
            return
          }
          const value: FieldValue | undefined = this.buildFieldValue(values[item.index])
          Logger.debug(`ListField delete field=${this.field} type=${this.type} value=${item.rawText}`, 'ListField')
          if (value) {
            deleteListValue(this.config!, this.type, this.field, value)
          } else {
            values.splice(item.index, 1)
          }
          this.updateItems()
          syncTopLevelField(this.config!.instance_id!, this.field, this.config!)
        })
    }
  }

  build() {
    List({ space: 10, scroller: this.scroller }) {
      if (this.items.length > 0) {
        ForEach(this.items, (item: ListFieldItemModel) => {
          ListItem() {
            ListFieldValue({ item: item })
              .width('100%')
              .onAreaChange((a, b) => {
                this.item_height = b.height.valueOf() as number
              })
          }
          .swipeAction({
            end: this.rightButton(item)
          })
        }, (item: ListFieldItemModel) => {
          return item.key
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
    .cachedCount(0, false)
    .height(this.comp_height)
    .width('100%')
  }
}
