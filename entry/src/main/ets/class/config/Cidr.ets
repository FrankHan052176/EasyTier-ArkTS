import { lane } from "../../util/Conversion"
import { FieldValue } from "./Basic"

function isIpAddr(value: string): boolean {
  return RegExp("^(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$").test(value)
}

function isMask(value: string): boolean {
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
export function CidrBuilder(value: Cidr) {
  Row() {
    Text(value.toString())
      .height((lane(1)-20)/3)
  }
  .width('100%')
  .justifyContent(FlexAlign.Center)
}

@ObservedV2
export class Cidr implements FieldValue {
  @Trace ip: string = "10.0.0.1"
  @Trace mask: string = "24"
  fromString(value: string): boolean {
    let arr = value.split("/")
    if (arr.length != 2 || !isMask(arr[1]) || !isIpAddr(arr[0])) {
      return false
    }else {
      this.ip = arr[0]
      this.mask = arr[1]
      return true
    }
  }
  toString(): string {
    return this.ip+"/"+this.mask
  }
}