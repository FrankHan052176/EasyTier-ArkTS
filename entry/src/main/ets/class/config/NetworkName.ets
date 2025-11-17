import { lane } from "../../util/Conversion"
import { FieldValue } from "./Basic"

@Builder
export function NetworkNameBuilder(value: NetworkName) {
  Row() {
    Text(value.toString())
      .height((lane(1)-20)/3)
  }
  .width('100%')
  .justifyContent(FlexAlign.Center)
}

@ObservedV2
export class NetworkName implements FieldValue {
  @Trace name: string = "easytier"
  fromString(value: string): boolean {
    this.name = value
    return true
  }
  toString(): string {
    return this.name
  }
}