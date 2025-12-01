import { lane } from "../../util/Conversion"
import { convertToProtocol, Protocol, protocolColor } from "../../util/ETConfig"
import { FieldValue } from "./Basic"
import { hdsEffect } from "@kit.UIDesignKit"
import { deviceInfo } from "@kit.BasicServicesKit"
import { LengthMetrics } from "@kit.ArkUI"

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

@Builder
function LightPoint(proto: Protocol) {
  Flex()
    .width(1)
    .height(1)
    .visualEffect(new hdsEffect.HdsEffectBuilder().pointLight({
      illuminatedType: hdsEffect.PointLightIlluminatedType.BORDER,
      options: {
        color: protocolColor(proto),
        intensity: 1,
        height: lane(1)*0.3,
        bloom: 0
      }
    }).buildEffect())
    .animation({
      curve: Curve.Ease,
      duration: 300
    })
}

@Builder
function ProtoBuilder(proto: Protocol) {
  if (deviceInfo.sdkApiVersion >= 20) {
    Row() {
      Text(proto.toString().toUpperCase())
        .fontSize(12)
        .fontColor(Color.White)
    }
    .borderRadius(8)
    .padding({top: 3, bottom: 3, left: 8, right: 8})
    .margin({left: 3, top: 3})
    .backgroundColor(protocolColor(proto))
    .visualEffect(new hdsEffect.HdsEffectBuilder().pointLight({
      illuminatedType: hdsEffect.PointLightIlluminatedType.BORDER,
    }).buildEffect())
    .overlay(
      LightPoint(proto),
      { align: Alignment.Center }
    )
  }else {
    Row() {
      Text(proto.toString().toUpperCase())
        .fontSize(12)
        .fontColor(Color.White)
    }
    .borderRadius(8)
    .padding({top: 3, bottom: 3, left: 8, right: 8})
    .margin({left: 3, top: 3})
    .backgroundColor(protocolColor(proto))
  }
}

@Builder
export function UrlBuilder(value: Url) {
  Row() {
    Text(value.domain+":"+value.port)
      .width('90%')
      .maxLines(2)
      .textOverflow({
        overflow: TextOverflow.Ellipsis
      })
      .textAlign(TextAlign.Center)
      .lineBreakStrategy(LineBreakStrategy.HIGH_QUALITY)
      .margin({top: 5})
  }
  .alignItems(VerticalAlign.Center)
  .justifyContent(FlexAlign.Center)
  .overlay(
    ProtoBuilder(value.proto),
    {
      align: Alignment.TopStart
    }
  )
  .height((lane(1)-10)/2)
  .width('100%')
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
            EditValue_Url!.proto = protocols[index as number]
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
              EditValue_Url!.domain = value
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
              EditValue_Url!.port = value
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
  toString(): string {
    return this.proto+"://"+this.domain+":"+this.port
  }
  checkValid(): boolean {
    return isPort(this.port) && isDomainOrIP(this.domain)
  }
}