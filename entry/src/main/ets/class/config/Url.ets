import { lane } from "../../util/Conversion"
import { convertToProtocol, Protocol, protocolBGColor, protocolColor } from "../../util/ETConfig"
import { FieldValue } from "./Basic"
import { hdsEffect } from "@kit.UIDesignKit"
import { deviceInfo } from "@kit.BasicServicesKit"
import { LengthMetrics } from "@kit.ArkUI"
import { AppManager, Svp2fp } from "../../AppManager"

function isDomainOrIP(value: string): boolean {
  return /^(((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)|([a-zA-Z0-9][-a-zA-Z0-9]*\.)+[a-zA-Z]{2,})$/.test(value)
}

function isPort(value: string): boolean {
  try {
    let num = Number.parseInt(value)
    if (num >= 0 && num <= 65535) {
      return true
    }else {
      return false
    }
  }catch (e) {
    return false
  }
}

@ComponentV2
export struct ProtoBuilder {
  @Param @Require proto: Protocol
  build() {
    Text(this.proto.toString().toUpperCase())
      .fontSize(11)
      .fontColor(protocolColor(this.proto))
      .fontWeight(FontWeight.Bold)
      .borderRadius(6)
      .padding({top: 4, bottom: 4, left: 6, right: 6})
      .backgroundColor(protocolBGColor(this.proto))
  }

}

@Builder
export function UrlBuilder(value: Url) {
  Row({space: 8}) {
    Row() {
      SymbolGlyph($r("sys.symbol.worldclock"))
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
        ProtoBuilder({proto: value.proto})
        Text(value.domain)
          .layoutWeight(100)
          .maxLines(1)
          .textOverflow({
            overflow: TextOverflow.Ellipsis
          })
          .textAlign(TextAlign.Start)
      }
      .width('100%')
      .justifyContent(FlexAlign.Start)
      Text(value.port)
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

@Builder
export function ListenerBuilder(value: Url) {
  Row({space: 8}) {
    Row() {
      SymbolGlyph($r("sys.symbol.dot_radiowaves_left_and_right"))
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
        ProtoBuilder({proto: value.proto})
        Text(value.domain)
          .layoutWeight(100)
          .maxLines(1)
          .textOverflow({
            overflow: TextOverflow.Ellipsis
          })
          .textAlign(TextAlign.Start)
      }
      .width('100%')
      .justifyContent(FlexAlign.Start)
      Text(value.port)
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

@Extend(Text)
function tips() {
  .width('100%')
  .fontSize(14)
  .fontColor($r("sys.color.font_secondary"))
  .textAlign(TextAlign.Center)
}

@Extend(TextInput)
function underline(textAlign: TextAlign = TextAlign.Center) {
  .padding({left: 1, right: 1, top: 5, bottom: 5})
  .backgroundColor(Color.Transparent)
  .border({
    width: {
      start: LengthMetrics.vp(0),
      end: LengthMetrics.vp(0),
      top: LengthMetrics.vp(0),
      bottom: LengthMetrics.vp(1)
    },
    color: {
      bottom: $r("sys.color.comp_divider")
    },
    radius: {
      bottomStart: LengthMetrics.vp(0),
      bottomEnd: LengthMetrics.vp(0)
    },
    style: {
      bottom: BorderStyle.Solid
    }
  })
  .textAlign(textAlign)
}

export let EditValue_Url: Url | undefined
export function clearEditValue_Url() {
  EditValue_Url = undefined
}
export function setEditValue_Url(value: Url) {
  EditValue_Url = value
}
let protocols = [Protocol.TCP, Protocol.UDP, Protocol.QUIC, Protocol.WS, Protocol.WSS, Protocol.WG]

@ComponentV2
export struct UrlEditor {
  @Local domain: boolean = false
  @Local port: boolean = false

  build() {
    Column() {
      Row() {
        TextPicker({ range: protocols, selected: protocols.indexOf(EditValue_Url!.proto)})
          .onChange((_value: string | string[], index: number | number[]) => {
            if (EditValue_Url) {
              EditValue_Url.proto = protocols[index as number]
            }
          })
          .canLoop(false)
          .defaultPickerItemHeight(36)
          .width(70)
        Text("://")
          .fontSize(18)
          .margin({left: 2, right: 2})
        TextInput({text: EditValue_Url!.domain})
          .underline()
          .width(150)
          .onChange((value: string) => {
            if (isDomainOrIP(value)) {
              this.domain = false
              if (EditValue_Url) {
                EditValue_Url.domain = value
              }
            }else {
              this.domain = true
            }
          })
        Text(":")
          .fontSize(18)
          .margin({left: 2, right: 2})
        TextInput({text: EditValue_Url!.port})
          .underline()
          .width(60)
          .maxLength(5)
          .type(InputType.Number)
          .onChange((value: string) => {
            if (isPort(value)) {
              this.port = false
              if (EditValue_Url) {
                EditValue_Url.port = value
              }
            }else {
              this.port = true
            }
          })
      }
      .width('100%')
      Text(`
协议、域名、端口请分别设置
      `)
        .tips()
      Blank()
        .width('100%')
        .height(100)
    }
    .width('90%')
  }
}

@ObservedV2
export class Url implements FieldValue {
  @Trace proto: Protocol = Protocol.TCP
  @Trace domain: string = "public.easytier.top"
  @Trace port: string = "11010"
  fieldName: string | undefined
  @Monitor("proto","domain","port")
  onChange(monitor: IMonitor) {
    if (this.checkValid()) {
      let config = AppManager.data.configUUIDMap.get(AppManager.data.editingInstance ?? "")
      if (!config) return
      if (!this.fieldName) return
      let arr = config[this.fieldName] as string[]
      let old = (monitor.value("proto")?.before ?? this.proto) + "://"
        + (monitor.value("domain")?.before ?? this.domain) + ":"
        + (monitor.value("port")?.before ?? this.port)
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
      let arr1 = arr[1].split(":")
      if (arr.length != 2 || !isPort(arr1[1]) || !isDomainOrIP(arr1[0])) {
        return false
      }else {
        this.domain = arr1[0]
        this.port = arr1[1]
        return true
      }
    }
  }
  readFrom(value: string): Url | undefined {
    let arr = value.split("://")
    if (arr.length != 2) {
      return undefined
    }else {
      this.proto = convertToProtocol(arr[0])
      let arr1 = arr[1].split(":")
      if (arr.length != 2 || !isPort(arr1[1]) || !isDomainOrIP(arr1[0])) {
        return undefined
      }else {
        this.domain = arr1[0]
        this.port = arr1[1]
        return this
      }
    }
  }
  toString(): string {
    return this.proto+"://"+this.domain+":"+this.port
  }
  checkValid(): boolean {
    return isPort(this.port) && isDomainOrIP(this.domain)
  }
  bind(fieldName: string): Url {
    this.fieldName = fieldName
    return this
  }
}