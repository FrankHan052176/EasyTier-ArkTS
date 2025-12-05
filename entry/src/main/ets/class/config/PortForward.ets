import { lane } from "../../util/Conversion"
import { convertToProtocol, Protocol, protocolBGColor, protocolColor } from "../../util/ETConfig"
import { FieldValue } from "./Basic"
import { hdsEffect } from "@kit.UIDesignKit"
import { deviceInfo } from "@kit.BasicServicesKit"
import { AppManager, Svp2fp } from "../../AppManager"

function isIpAddr(value: string): boolean {
  return RegExp("^(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$").test(value)
}

function isPort(value: string): boolean {
  if (Number.isInteger(value)) {
    try {
      let num = Number.parseInt(value)
      if (num >= 0 && num <= 32) {
        return true
      }
    }catch (e) {
      return false
    }
  }
  return false
}


@Builder
function ProtoBuilder(proto: Protocol) {
  Text(proto.toString().toUpperCase())
    .fontSize(11)
    .fontColor(protocolColor(proto))
    .fontWeight(FontWeight.Bold)
    .borderRadius(6)
    .padding({top: 4, bottom: 4, left: 6, right: 6})
    .backgroundColor(protocolBGColor(proto))
}

@Builder
export function PortForwardBuilder(value: PortForward) {
  Row({space: 8}) {
    Row() {
      SymbolGlyph($r("sys.symbol.arrow_bounce_right"))
        .fontSize(Svp2fp(24))
        .fontColor([$r("sys.color.font_secondary")])
    }
    .backgroundColor($r("sys.color.comp_background_tertiary"))
    .padding(10)
    .borderRadius(8)
    .alignItems(VerticalAlign.Center)
    .justifyContent(FlexAlign.Center)
    Column({space: 4}) {
      Row({space: 8}) {
        ProtoBuilder(value.proto)
        Text(value.to+":"+value.to_port)
          .layoutWeight(100)
          .maxLines(1)
          .textOverflow({
            overflow: TextOverflow.Ellipsis
          })
          .textAlign(TextAlign.Start)
      }
      .width('100%')
      .justifyContent(FlexAlign.Start)
      Text(value.from+":"+value.from_port)
        .fontSize(14)
        .width('100%')
        .fontColor($r("sys.color.font_tertiary"))
        .maxLines(1)
        .textOverflow({
          overflow: TextOverflow.Ellipsis
        })
        .textAlign(TextAlign.Start)
    }
    .alignItems(HorizontalAlign.Start)
    .layoutWeight(100)
  }
  .width('100%')
  .justifyContent(FlexAlign.Start)
}

@ObservedV2
export class PortForward implements FieldValue {
  @Trace proto: Protocol = Protocol.TCP
  @Trace from: string = "10.0.0.1"
  @Trace from_port: string = "11010"
  @Trace to: string = "10.0.0.2"
  @Trace to_port: string = "11010"
  fieldName: string | undefined
  @Monitor("proto","from","from_port","to","to_port")
  onChange(monitor: IMonitor) {
    if (this.checkValid()) {
      let config = AppManager.data.configUUIDMap.get(AppManager.data.editingInstance ?? "")
      if (!config) return
      if (!this.fieldName) return
      let arr = config[this.fieldName] as string[]
      let old = (monitor.value("proto")?.before ?? this.proto) + "://"
        + (monitor.value("from")?.before ?? this.from) + ":"
        + (monitor.value("from_port")?.before ?? this.from_port) + "/"
        + (monitor.value("to")?.before ?? this.to) + ":"
        + (monitor.value("to_port")?.before ?? this.to_port)
      let index = arr.indexOf(old)
      if (index < 0) return
      arr[index] = this.toString()
    }
  }
  fromString(value: string): boolean {
    let arr = value.split("://")
    if (arr.length != 2) {
      return false
    }else {
      this.proto = convertToProtocol(arr[0])
      let arr1 = arr[1].split("/")
      if (arr.length != 2) {
        return false
      }else {
        let arr2 = arr1[0].split(":")
        let arr3 = arr1[1].split(":")
        if (!isIpAddr(arr2[0]) || !isPort(arr2[1]) || !isIpAddr(arr3[0]) || !isPort(arr3[1])) {
          return false
        }else {
          this.from = arr2[0]
          this.from_port = arr2[1]
          this.to = arr3[0]
          this.to_port = arr3[1]
          return true
        }
      }
    }
  }
  readFrom(value: string): PortForward | undefined {
    let arr = value.split("://")
    if (arr.length != 2) {
      return undefined
    }else {
      this.proto = convertToProtocol(arr[0])
      let arr1 = arr[1].split("/")
      if (arr.length != 2) {
        return undefined
      }else {
        let arr2 = arr1[0].split(":")
        let arr3 = arr1[1].split(":")
        if (!isIpAddr(arr2[0]) || !isPort(arr2[1]) || !isIpAddr(arr3[0]) || !isPort(arr3[1])) {
          return undefined
        }else {
          this.from = arr2[0]
          this.from_port = arr2[1]
          this.to = arr3[0]
          this.to_port = arr3[1]
          return this
        }
      }
    }
  }
  toString(): string {
    return this.proto.toString()+"://"+this.from+":"+this.from_port+"/"+this.to+":"+this.to_port
  }
  checkValid(): boolean {
    return isIpAddr(this.from) && isIpAddr(this.to) && isPort(this.from_port) && isPort(this.to_port)
  }
  bind(fieldName: string): PortForward {
    this.fieldName = fieldName
    return this
  }
}