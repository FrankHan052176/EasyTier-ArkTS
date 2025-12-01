import { lane } from "../../util/Conversion"
import { FieldValue } from "./Basic"
import { LengthMetrics } from "@kit.ArkUI"
import { Logger } from "../../util/Logger"

function isIpAddr(value: string): boolean {
  return RegExp("^(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$").test(value)
}

function isMask(value: string): boolean {
  try {
    let num = Number.parseInt(value)
    if (num >= 0 && num <= 32) {
      return true
    }else {
      return false
    }
  }catch (e) {
    return false
  }
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

export let EditValue_Cidr: Cidr | undefined
export function clearEditValue_Cidr() {
  EditValue_Cidr = undefined
}
export function setEditValue_Cidr(cidr: Cidr) {
  EditValue_Cidr = cidr
}

@ComponentV2
export struct CidrEditor {
  @Local ip: boolean = false
  @Local Mask: boolean = false

  build() {
    Column() {
      Row() {
        TextInput({text: EditValue_Cidr!.ip})
          .underline()
          .width(70)
          .onChange((value: string) => {
            if (isIpAddr(value)) {
              this.ip = false
              EditValue_Cidr!.ip = value
            }else {
              this.ip = true
            }
          })
        Text("/")
          .fontSize(18)
          .margin({left: 2, right: 2})
        TextInput({text: ""+EditValue_Cidr!.mask})
          .underline()
          .maxLength(2)
          .width(30)
          .onChange((value: string) => {
            if (isMask(value)) {
              this.Mask = false
              EditValue_Cidr!.mask = value
            }else {
              this.Mask = true
            }
          })
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
      Text(`
请设置网段，如10.0.0.0/24
      `)
        .tips()
      Blank()
        .width('100%')
        .height(100)
    }
    .width('90%')
  }
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
  @Trace ip: string = "10.0.0.0"
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
  checkValid(): boolean {
    return isMask(this.mask) && isIpAddr(this.ip)
  }
}