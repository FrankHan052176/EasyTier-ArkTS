import { convertToProtocol, Protocol, protocolBGColor, protocolColor, protocols } from '../../util/Conversion'
import { FieldValue } from './Basic'
import { LengthMetrics } from '@kit.ArkUI'
import { AppManager, Svp2fp } from '../../AppManager'
import { ProtocolSelector } from '../../components/util/ProtocolSelector'
import { ConfigJson } from '../../config/schema/SchemaConfig'

function isDomainOrIP(value: string): boolean {
  return /^(((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)|([a-zA-Z0-9][-a-zA-Z0-9]*\.)+[a-zA-Z]{2,})$/.test(value)
}

function isDomainIPPathOrIdentifier(value: string): boolean {
  if (value.length === 0) {
    return false
  }
  return !/\s/.test(value)
}

function isPort(value: string): boolean {
  try {
    let num = Number.parseInt(value)
    if (num >= 0 && num <= 65535) {
      return true
    } else {
      return false
    }
  } catch (e) {
    return false
  }
}

interface ParsedUrlValue {
  domain: string
  port: string
}

function protocolRequiresPort(protocol: Protocol): boolean {
  return protocol === Protocol.TCP || protocol === Protocol.UDP || protocol === Protocol.QUIC ||
    protocol === Protocol.WG || protocol === Protocol.TCP6 || protocol === Protocol.UDP6 ||
    protocol === Protocol.QUIC6 || protocol === Protocol.WG6
}

function protocolSupportsOptionalPort(protocol: Protocol): boolean {
  return protocol === Protocol.WS || protocol === Protocol.WSS || protocol === Protocol.HTTP || protocol === Protocol.HTTPS ||
    protocol === Protocol.WS6 || protocol === Protocol.WSS6
}

function protocolUsesRawTarget(protocol: Protocol): boolean {
  return protocol === Protocol.TXT || protocol === Protocol.RING || protocol === Protocol.SRV
}

function splitHostAndPort(value: string): ParsedUrlValue | undefined {
  if (value.startsWith('[')) {
    const closing = value.indexOf(']')
    if (closing < 0) {
      return undefined
    }
    const domain = value.substring(0, closing + 1)
    const remain = value.substring(closing + 1)
    if (!remain.startsWith(':')) {
      return undefined
    }
    const port = remain.substring(1)
    const parsed: ParsedUrlValue = { domain, port }
    return parsed
  }
  const index = value.lastIndexOf(':')
  if (index <= 0 || index === value.length - 1) {
    return undefined
  }
  const parsed: ParsedUrlValue = {
    domain: value.substring(0, index),
    port: value.substring(index + 1)
  }
  return parsed
}

function parseUrlValue(proto: Protocol, rawValue: string): ParsedUrlValue | undefined {
  const value = rawValue.trim()
  if (protocolUsesRawTarget(proto)) {
    if (!isDomainIPPathOrIdentifier(value)) {
      return undefined
    }
    const parsed: ParsedUrlValue = { domain: value, port: '' }
    return parsed
  }

  if (protocolRequiresPort(proto)) {
    const parsed = splitHostAndPort(value)
    if (!parsed || !isPort(parsed.port) || !isDomainIPPathOrIdentifier(parsed.domain)) {
      return undefined
    }
    return parsed
  }

  if (protocolSupportsOptionalPort(proto)) {
    const parsed = splitHostAndPort(value)
    if (!parsed) {
      if (!isDomainIPPathOrIdentifier(value)) {
        return undefined
      }
      const noPortParsed: ParsedUrlValue = { domain: value, port: '' }
      return noPortParsed
    }
    if (!isPort(parsed.port) || !isDomainIPPathOrIdentifier(parsed.domain)) {
      return undefined
    }
    return parsed
  }

  return undefined
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
      .padding({
        top: 4,
        bottom: 4,
        left: 6,
        right: 6
      })
      .backgroundColor(protocolBGColor(this.proto))
  }
}

@Builder
export function UrlBuilder(value: Url) {
  Row({ space: 8 }) {
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

    Column({ space: 4 }) {
      Row({ space: 8 }) {
        ProtoBuilder({ proto: value.proto })
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

      if (!protocolUsesRawTarget(value.proto)) {
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
    }
    .alignItems(HorizontalAlign.Start)
    .layoutWeight(100)
  }
  .width('100%')
  .justifyContent(FlexAlign.Start)
}

@Builder
export function ListenerBuilder(value: Url) {
  Row({ space: 8 }) {
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

    Column({ space: 4 }) {
      Row({ space: 8 }) {
        ProtoBuilder({ proto: value.proto })
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

      if (!protocolUsesRawTarget(value.proto)) {
        Text(value.port.length > 0 ? value.port : "默认端口")
          .fontSize(14)
          .width('100%')
          .fontColor($r("sys.color.font_tertiary"))
          .maxLines(1)
          .textOverflow({
            overflow: TextOverflow.Ellipsis
          })
          .textAlign(TextAlign.Start)
      }
    }
    .alignItems(HorizontalAlign.Start)
    .layoutWeight(100)
  }
  .width('100%')
  .justifyContent(FlexAlign.Start)
}

export let EditValue_Url: Url | undefined

export function clearEditValue_Url() {
  EditValue_Url = undefined
}

export function setEditValue_Url(value: Url) {
  EditValue_Url = value
}

@ComponentV2
export struct UrlEditor {
  @Param protocolArr: Protocol[] = protocols
  @Local domain: boolean = false
  @Local port: boolean = false
  @Local protocol: Protocol = EditValue_Url!.proto

  build() {
    Column() {
      Column({ space: 8 }) {
        // Protocol Section
        Row() {
          Text("协议类型")
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor($r("sys.color.font_primary"))
          Blank()
          ProtocolSelector({
            protocols: this.protocolArr,
            selected: this.protocol,
            onChange: (protocol) => {
              EditValue_Url!.proto = protocol
              this.protocol = protocol
            }
          })
        }
        .width('100%')
        .justifyContent(FlexAlign.SpaceBetween)
        .alignItems(VerticalAlign.Center)
        .padding({ left: 4, right: 4 })

        Divider().color($r("sys.color.comp_divider"))

        // Address Section
        Column({ space: 8 }) {
          Text("地址与端口")
            .fontSize(14)
            .fontColor($r("sys.color.font_secondary"))
            .width('100%')

          Row({ space: 8 }) {
            TextInput({ text: EditValue_Url!.domain, placeholder: "IP 或 域名" })
              .layoutWeight(3)
              .backgroundColor($r("sys.color.comp_background_tertiary"))
              .borderRadius(8)
              .padding(10)
              .onChange((value: string) => {
                if (isDomainIPPathOrIdentifier(value)) {
                  this.domain = false
                  if (EditValue_Url) {
                    EditValue_Url.domain = value
                  }
                } else {
                  this.domain = true
                }
              })

            if (!protocolUsesRawTarget(EditValue_Url!.proto)) {
              Text(":")
                .fontSize(16)
                .fontWeight(FontWeight.Bold)
                .fontColor($r("sys.color.font_tertiary"))

              TextInput({ text: EditValue_Url!.port, placeholder: protocolSupportsOptionalPort(EditValue_Url!.proto) ? "端口(可选)" : "端口" })
                .layoutWeight(1)
                .maxLength(5)
                .type(InputType.Number)
                .backgroundColor($r("sys.color.comp_background_tertiary"))
                .borderRadius(8)
                .padding(10)
                .textAlign(TextAlign.Center)
                .onChange((value: string) => {
                  if (value.length === 0 && protocolSupportsOptionalPort(EditValue_Url!.proto)) {
                    this.port = false
                    if (EditValue_Url) {
                      EditValue_Url.port = value
                    }
                  } else if (isPort(value)) {
                    this.port = false
                    if (EditValue_Url) {
                      EditValue_Url.port = value
                    }
                  } else {
                    this.port = true
                  }
                })
            }
          }
          .width('100%')
        }
        .width('100%')

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
export class Url implements FieldValue {
  @Trace proto: Protocol = Protocol.TCP
  @Trace domain: string = "public.easytier.top"
  @Trace port: string = "11010"
  fieldName: string | undefined

  @Monitor("proto", "domain", "port")
  onChange(monitor: IMonitor) {
    if (this.checkValid()) {
      let config: ConfigJson = AppManager.easytier.getEditingConfig()
      if (!config) {
        return
      }
      if (!this.fieldName) {
        return
      }
      let arr = config[this.fieldName] as string[]
      const oldProto = monitor.value("proto")?.before as Protocol ?? this.proto
      const oldDomain = monitor.value("domain")?.before as string ?? this.domain
      const oldPort = monitor.value("port")?.before as string ?? this.port
      let old = oldProto + "://" + oldDomain
      if (!protocolUsesRawTarget(oldProto) && oldPort.length > 0) {
        old += ":" + oldPort
      }
      let index = arr.indexOf(old)
      if (index < 0) {
        return
      }
      arr[index] = this.toString()
    }
  }

  fromString(value: string): boolean {
    value = value.replace(/['"]/g, '')
    let arr = value.split("://")
    if (arr.length != 2) {
      return false
    } else {
      this.proto = convertToProtocol(arr[0])
      const parsed = parseUrlValue(this.proto, arr[1])
      if (!parsed) {
        return false
      }
      this.domain = parsed.domain
      this.port = parsed.port
      return true
    }
  }

  readFrom(value: string): Url | undefined {
    value = value.replace(/['"]/g, '')
    let arr = value.split("://")
    if (arr.length != 2) {
      return undefined
    } else {
      this.proto = convertToProtocol(arr[0])
      const parsed = parseUrlValue(this.proto, arr[1])
      if (!parsed) {
        return undefined
      }
      this.domain = parsed.domain
      this.port = parsed.port
      return this
    }
  }

  toString(): string {
    if (protocolUsesRawTarget(this.proto)) {
      return this.proto + "://" + this.domain
    }
    if (this.port.length === 0 && protocolSupportsOptionalPort(this.proto)) {
      return this.proto + "://" + this.domain
    }
    return this.proto + "://" + this.domain + ":" + this.port
  }

  checkValid(): boolean {
    if (!isDomainIPPathOrIdentifier(this.domain)) {
      return false
    }
    if (protocolUsesRawTarget(this.proto)) {
      return true
    }
    if (protocolSupportsOptionalPort(this.proto) && this.port.length === 0) {
      return true
    }
    return isPort(this.port)
  }

  bind(fieldName: string): Url {
    this.fieldName = fieldName
    return this
  }
}
