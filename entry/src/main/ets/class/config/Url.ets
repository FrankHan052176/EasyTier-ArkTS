import { convertToProtocol, Protocol, protocolBGColor, protocolColor, protocols } from '../../util/Conversion'
import { FieldValue } from './Basic'
import { LengthMetrics } from '@kit.ArkUI'
import { AppManager, Svp2fp } from '../../AppManager'
import { ProtocolSelector } from '../../components/util/ProtocolSelector'
import { ConfigJson } from '../../SchemaConfig'

function isDomainOrIP(value: string): boolean {
  return /^(((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)|([a-zA-Z0-9][-a-zA-Z0-9]*\.)+[a-zA-Z]{2,})$/.test(value)
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

      if (value.proto != Protocol.TXT) {
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
                if (isDomainOrIP(value)) {
                  this.domain = false
                  if (EditValue_Url) {
                    EditValue_Url.domain = value
                  }
                } else {
                  this.domain = true
                }
              })

            Text(":")
              .fontSize(16)
              .fontWeight(FontWeight.Bold)
              .fontColor($r("sys.color.font_tertiary"))

            TextInput({ text: EditValue_Url!.port, placeholder: "端口" })
              .layoutWeight(1)
              .maxLength(5)
              .type(InputType.Number)
              .backgroundColor($r("sys.color.comp_background_tertiary"))
              .borderRadius(8)
              .padding(10)
              .textAlign(TextAlign.Center)
              .onChange((value: string) => {
                if (isPort(value)) {
                  this.port = false
                  if (EditValue_Url) {
                    EditValue_Url.port = value
                  }
                } else {
                  this.port = true
                }
              })
              .enabled(EditValue_Url?.proto !== Protocol.TXT)
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
      let old = (monitor.value("proto")?.before ?? this.proto) + "://"
        + (monitor.value("domain")?.before ?? this.domain) + ":"
        + (monitor.value("port")?.before ?? this.port)
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
      if (this.proto != Protocol.TXT) {
        let arr1 = arr[1].split(":")
        if (arr.length != 2 || !isPort(arr1[1]) || !isDomainOrIP(arr1[0])) {
          return false
        } else {
          this.domain = arr1[0]
          this.port = arr1[1]
          return true
        }
      }else {
        if (isDomainOrIP(arr[1])) {
          this.domain = arr[1]
          return true
        }else {
          return false
        }
      }
    }
  }

  readFrom(value: string): Url | undefined {
    value = value.replace(/['"]/g, '')
    let arr = value.split("://")
    if (arr.length != 2) {
      return undefined
    } else {
      this.proto = convertToProtocol(arr[0])
      if (this.proto != Protocol.TXT) {
        let arr1 = arr[1].split(":")
        if (arr.length != 2 || !isPort(arr1[1]) || !isDomainOrIP(arr1[0])) {
          return undefined
        } else {
          this.domain = arr1[0]
          this.port = arr1[1]
          return this
        }
      }else {
        if (isDomainOrIP(arr[1])) {
          this.domain = arr[1]
          return this
        }else {
          return undefined
        }
      }
    }
  }

  toString(): string {
    if (this.proto === Protocol.TXT) {
      return this.proto + "://" + this.domain
    } else {
      return this.proto + "://" + this.domain + ":" + this.port
    }
  }

  checkValid(): boolean {
    return isPort(this.port) && isDomainOrIP(this.domain)
  }

  bind(fieldName: string): Url {
    this.fieldName = fieldName
    return this
  }
}
