import { lane } from "../../util/Conversion"
import { convertToProtocol, Protocol, protocolColor } from "../../util/ETConfig"
import { FieldValue } from "./Basic"
import { hdsEffect } from "@kit.UIDesignKit"
import { deviceInfo } from "@kit.BasicServicesKit"

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
export function PortForwardBuilder(value: PortForward) {
  Row() {
    SymbolGlyph($r("sys.symbol.arrowshape_turn_up_left_fill"))
      .fontColor([$r("sys.color.font_primary")])
      .fontSize(14).margin({top: 5})
      .rotate({
        angle: -135,
        centerX: '50%',
        centerY: '50%'
      })
    Column() {
      Text(value.from+":"+value.from_port)
        .fontSize(14)
        .width('100%')
        .maxLines(1)
        .textOverflow({
          overflow: TextOverflow.MARQUEE
        })
        .margin({bottom: 3})
      Text(value.to+":"+value.to_port)
        .fontSize(14)
        .width('100%')
        .maxLines(1)
        .textOverflow({
          overflow: TextOverflow.MARQUEE
        })
    }
    .width('80%')
    .alignItems(HorizontalAlign.Center)
    .padding({right: 5}).margin({top: 5})
  }
  .alignItems(VerticalAlign.Center)
  .justifyContent(FlexAlign.End)
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
export class PortForward implements FieldValue {
  @Trace proto: Protocol = Protocol.TCP
  @Trace from: string = "10.0.0.1"
  @Trace from_port: string = "11010"
  @Trace to: string = "10.0.0.2"
  @Trace to_port: string = "11010"
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
  toString(): string {
    return this.proto+"://"+this.from+":"+this.from_port+"/"+this.to+":"+this.to_port
  }
  checkValid(): boolean {
    return isIpAddr(this.from) && isIpAddr(this.to) && isPort(this.from_port) && isPort(this.to_port)
  }
}