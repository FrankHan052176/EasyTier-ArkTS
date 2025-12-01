import { lane } from "../../util/Conversion"
import { convertToProtocol, Protocol, protocolColor } from "../../util/ETConfig"
import { FieldValue } from "./Basic"
import { hdsEffect } from "@kit.UIDesignKit"
import { deviceInfo } from "@kit.BasicServicesKit"

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
}