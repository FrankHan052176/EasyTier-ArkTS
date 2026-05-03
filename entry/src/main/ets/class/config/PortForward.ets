import {
  convertToProtocol,
  Protocol,
  protocolBGColor,
  protocolColor,
  protocolsOnlyTcpAndUdp
} from '../../util/Conversion'
import { FieldValue } from './Basic'
import { AppManager, Svp2fp } from '../../AppManager'
import { LengthMetrics } from '@kit.ArkUI'
import { ProtocolSelector } from '../../components/util/ProtocolSelector'
import { ConfigJson } from '../../config/schema/SchemaConfig'

function isIpAddr(value: string): boolean {
  return RegExp("^(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$")
    .test(value)
}

function isPort(value: string): boolean {
  try {
    let num = Number.parseInt(value)
    if (num >= 0 && num <= 65535) {
      return true
    }
    return false
  } catch (e) {
    return false
  }
}


@Builder
function ProtoBuilder(proto: Protocol) {
  Text(proto.toString().toUpperCase())
    .fontSize(11)
    .fontColor(protocolColor(proto))
    .fontWeight(FontWeight.Bold)
    .borderRadius(6)
    .padding({
      top: 4,
      bottom: 4,
      left: 6,
      right: 6
    })
    .backgroundColor(protocolBGColor(proto))
}

@Builder
export function PortForwardBuilder(value: PortForward) {
  Row({ space: 8 }) {
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

    Column({ space: 4 }) {
      Row({ space: 8 }) {
        ProtoBuilder(value.proto)
        Text(value.to + ":" + value.to_port)
          .layoutWeight(100)
          .maxLines(1)
          .textOverflow({
            overflow: TextOverflow.Ellipsis
          })
          .textAlign(TextAlign.Start)
      }
      .width('100%')
      .justifyContent(FlexAlign.Start)

      Text(value.from + ":" + value.from_port)
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
  .textAlign(TextAlign.Start)
}

@Extend(TextInput)
function underline(textAlign: TextAlign = TextAlign.Center) {
  .padding({
    left: 1,
    right: 1,
    top: 5,
    bottom: 5
  })
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

export let EditValue_PortForward: PortForward | undefined

export function clearEditValue_PortForward() {
  EditValue_PortForward = undefined
}

export function setEditValue_PortForward(value: PortForward) {
  EditValue_PortForward = value
}

@ComponentV2
export struct PortForwardEditor {
  @Local domain: boolean = false
  @Local port: boolean = false

  @Builder
  inputGroup(title: string, ip: string, port: string, onIpChange: (value: string) => void,
    onPortChange: (value: string) => void) {
    Column({ space: 8 }) {
      Text(title)
        .fontSize(14)
        .fontColor($r("sys.color.font_secondary"))
        .width('100%')

      Row({ space: 8 }) {
        TextInput({ text: ip, placeholder: "IP地址 / 域名" })
          .layoutWeight(3)
          .backgroundColor($r("sys.color.comp_background_tertiary"))
          .borderRadius(8)
          .padding(10)
          .onChange(onIpChange)

        Text(":")
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor($r("sys.color.font_tertiary"))

        TextInput({ text: port, placeholder: "端口" })
          .layoutWeight(1)
          .type(InputType.Number)
          .maxLength(5)
          .backgroundColor($r("sys.color.comp_background_tertiary"))
          .borderRadius(8)
          .padding(10)
          .textAlign(TextAlign.Center)
          .onChange(onPortChange)
      }
      .width('100%')
    }
    .width('100%')
  }

  build() {
    Column() {
      Column({ space: 8 }) {
        // Protocol Section
        Row() {
          Text("协议类型")
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
          Blank()
          ProtocolSelector({
            protocols: protocolsOnlyTcpAndUdp,
            selected: EditValue_PortForward!.proto,
            onChange: (p) => {
              if (EditValue_PortForward) {
                EditValue_PortForward.proto = p
              }
            }
          })
        }
        .width('100%')
        .justifyContent(FlexAlign.SpaceBetween)
        .alignItems(VerticalAlign.Center)
        .padding({ bottom: 4 })

        Divider().color($r("sys.color.comp_divider"))

        // Source Address
        this.inputGroup(
          "源地址 (本地监听)",
          EditValue_PortForward!.from,
          EditValue_PortForward!.from_port,
          (value) => {
            if (isIpAddr(value)) {
              this.domain = false
              if (EditValue_PortForward) {
                EditValue_PortForward.from = value
              }
            } else {
              this.domain = true
            }
          },
          (value) => {
            if (isPort(value)) {
              this.port = false
              if (EditValue_PortForward) {
                EditValue_PortForward.from_port = value
              }
            } else {
              this.port = true
            }
          }
        )

        Divider().color($r("sys.color.comp_divider"))

        // Destination Address
        this.inputGroup(
          "目标地址 (转发至)",
          EditValue_PortForward!.to,
          EditValue_PortForward!.to_port,
          (value) => {
            if (isIpAddr(value)) {
              this.domain = false
              if (EditValue_PortForward) {
                EditValue_PortForward.to = value
              }
            } else {
              this.domain = true
            }
          },
          (value) => {
            if (isPort(value)) {
              this.port = false
              if (EditValue_PortForward) {
                EditValue_PortForward.to_port = value
              }
            } else {
              this.port = true
            }
          }
        )
        Row() {
          SymbolGlyph($r('sys.symbol.info_circle'))
            .fontSize(16)
            .fontColor([$r('sys.color.font_secondary')])
            .margin({ right: 8 })
          Text("协议、域名、端口请分别设置")
            .fontSize(12)
            .fontColor($r('sys.color.font_secondary'))
        }
        .width('100%')
        .padding({ top: 12 })
        .alignItems(VerticalAlign.Top)
      }
      .width('90%')
      .padding(16)
      .backgroundColor($r("sys.color.comp_background_primary"))
      .borderRadius(16)

      Blank()
        .width('100%')
        .height(100)
    }
  }
}

@ObservedV2
export class PortForward implements FieldValue {
  @Trace proto: Protocol = Protocol.TCP
  @Trace from: string = "0.0.0.0"
  @Trace from_port: string = "11010"
  @Trace to: string = "10.0.0.2"
  @Trace to_port: string = "11010"
  fieldName: string | undefined

  @Monitor("proto", "from", "from_port", "to", "to_port")
  onChange(monitor: IMonitor) {
    if (this.checkValid()) {
      let config: ConfigJson = AppManager.easytier.getEditingConfig()
      if (!config) {
        return
      }
      if (!this.fieldName) {
        return
      }
      let arr: ESObject[] = config[this.fieldName] as ESObject[]
      let old: ESObject = {
        bind_ip: (monitor.value("from")?.before ?? this.from) as string,
        bind_port: Number.parseInt((monitor.value("from_port")?.before ?? this.from_port) as string),
        dst_ip: (monitor.value("to")?.before ?? this.to) as string,
        dst_port: Number.parseInt((monitor.value("to_port")?.before ?? this.to_port) as string),
        proto: monitor.value("proto")?.before?.toString() ?? this.proto.toString()
      }
      let i = -1
      for (let index = 0; index < arr.length; index++) {
          const element: ESObject = arr[index];
        if (element.bind_ip === old.bind_ip &&
          element.bind_port === old.bind_port &&
          element.dst_ip === old.dst_ip &&
          element.dst_port === old.dst_port &&
          element.proto === old.proto
        ) {
          i = index
          break
        }
      }
      if (i < 0) {
        return
      }
      arr[i] = {
        bind_ip: this.from,
        bind_port: Number.parseInt(this.from_port),
        dst_ip: this.to,
        dst_port: Number.parseInt(this.to_port),
        proto: this.proto.toString()
      }
    }
  }

  fromString(value: string): boolean {
    value = value.replace(/['"]/g, '')
    let arr = value.split("://")
    if (arr.length != 2) {
      return false
    } else {
      this.proto = convertToProtocol(arr[0])
      let arr1 = arr[1].split("/")
      if (arr.length != 2) {
        return false
      } else {
        let arr2 = arr1[0].split(":")
        let arr3 = arr1[1].split(":")
        if (!isIpAddr(arr2[0]) || !isPort(arr2[1]) || !isIpAddr(arr3[0]) || !isPort(arr3[1])) {
          return false
        } else {
          this.from = arr2[0]
          this.from_port = arr2[1]
          this.to = arr3[0]
          this.to_port = arr3[1]
          return true
        }
      }
    }
  }

  readFrom(value: ESObject): PortForward | undefined {
    this.proto = convertToProtocol(value.proto)
    let bind_port = ("" + value.bind_port).replace(/['"]/g, '')
    let dst_port = ("" + value.dst_port).replace(/['"]/g, '')
    if (!isIpAddr(value.bind_ip) || !isPort(bind_port) || !isIpAddr(value.dst_ip) ||
      !isPort(dst_port)) {
      return undefined
    } else {
      this.from = value.bind_ip
      this.from_port = bind_port
      this.to = value.dst_ip
      this.to_port = dst_port
      return this
    }
  }

  toString(): string {
    return this.proto.toString() + "://" + this.from + ":" + this.from_port + "/" + this.to + ":" + this.to_port
  }

  toInterface(): ESObject {
    return {
      bind_ip: this.from,
      bind_port: Number.parseInt(this.from_port),
      dst_ip: this.to,
      dst_port: Number.parseInt(this.to_port),
      proto: this.proto.toString()
    }
  }

  checkValid(): boolean {
    return isIpAddr(this.from) && isIpAddr(this.to) && isPort(this.from_port) && isPort(this.to_port)
  }

  bind(fieldName: string): PortForward {
    this.fieldName = fieldName
    return this
  }
}
