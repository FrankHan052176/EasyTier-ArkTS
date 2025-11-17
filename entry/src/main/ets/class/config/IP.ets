import { lane } from "../../util/Conversion"
import { FieldValue } from "./Basic"

function isIpAddr(value: string): boolean {
  return RegExp("^(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$").test(value)
}

@Builder
export function IPBuilder(value: IP) {
  Row() {
    Text(value.toString())
      .height((lane(1)-20)/3)
  }
  .width('100%')
  .justifyContent(FlexAlign.Center)
}

@ObservedV2
export class IP implements FieldValue {
  @Trace ip: string = "10.0.0.1"
  fromString(value: string): boolean {
    if (isIpAddr(value)) {
      this.ip = value
      return true
    }else {
      return false
    }
  }
  toString(): string {
    return this.ip
  }
}