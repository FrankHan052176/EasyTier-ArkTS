import { FieldValue } from './Basic'
import { LengthMetrics } from '@kit.ArkUI'
import { AppManager, Svp2fp } from '../../AppManager'

function isIpAddr(value: string): boolean {
  return RegExp("^(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$")
    .test(value)
}

function isMask(value: string): boolean {
  try {
    let num = Number.parseInt(value)
    if (num >= 0 && num <= 32) {
      return true
    } else {
      return false
    }
  } catch (e) {
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
        TextInput({ text: EditValue_Cidr!.ip })
          .underline()
          .width(70)
          .onChange((value: string) => {
            if (isIpAddr(value)) {
              this.ip = false
              if (EditValue_Cidr) {
                EditValue_Cidr.ip = value
              }
            } else {
              this.ip = true
            }
          })
        Text("/")
          .fontSize(18)
          .margin({ left: 2, right: 2 })
        TextInput({ text: "" + EditValue_Cidr!.mask })
          .underline()
          .maxLength(2)
          .width(30)
          .onChange((value: string) => {
            if (isMask(value)) {
              this.Mask = false
              if (EditValue_Cidr) {
                EditValue_Cidr.mask = value
              }
            } else {
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
  Row({ space: 10 }) {
    Row() {
      SymbolGlyph($r("sys.symbol.arrow_triangle_merge"))
        .fontSize(Svp2fp(24))
        .fontColor([$r("sys.color.font_secondary")])
    }
    .backgroundColor($r("sys.color.comp_background_tertiary"))
    .padding(10)
    .borderRadius(8)
    .alignItems(VerticalAlign.Center)
    .justifyContent(FlexAlign.Center)

    Text(value.toString())
      .layoutWeight(100)
      .maxLines(1)
      .textOverflow({
        overflow: TextOverflow.Ellipsis
      })
      .fontSize(Svp2fp(18))
  }
  .width('100%')
  .justifyContent(FlexAlign.Start)
}

@Builder
export function RouteBuilder(value: Cidr) {
  Row({ space: 10 }) {
    Row() {
      SymbolGlyph($r("sys.symbol.arrow_triangle_divide"))
        .fontSize(Svp2fp(24))
        .fontColor([$r("sys.color.font_secondary")])
    }
    .backgroundColor($r("sys.color.comp_background_tertiary"))
    .padding(10)
    .borderRadius(8)
    .alignItems(VerticalAlign.Center)
    .justifyContent(FlexAlign.Center)

    Text(value.toString())
      .layoutWeight(100)
      .maxLines(1)
      .textOverflow({
        overflow: TextOverflow.Ellipsis
      })
      .fontSize(Svp2fp(18))
  }
  .width('100%')
  .justifyContent(FlexAlign.Start)
}

@ObservedV2
export class Cidr implements FieldValue {
  @Trace ip: string = "10.0.0.0"
  @Trace mask: string = "24"
  fieldName: string | undefined

  @Monitor("ip","mask")
  onChange(monitor: IMonitor) {
    if (this.checkValid()) {
      let config = AppManager.data.configUUIDMap.get(AppManager.data.editingInstance ?? "")
      if (!config) {
        return
      }
      if (!this.fieldName) {
        return
      }
      let arr = config[this.fieldName] as string[]
      let old = (monitor.value("ip")?.before ?? this.ip) + "/" + (monitor.value("mask")?.before ?? this.mask)
      let index = arr.indexOf(old)
      if (index < 0) {
        return
      }
      arr[index] = this.toString()
    }
  }

  fromString(value: string): boolean {
    let arr = value.split("/")
    if (arr.length != 2 || !isMask(arr[1]) || !isIpAddr(arr[0])) {
      return false
    } else {
      this.ip = arr[0]
      this.mask = arr[1]
      return true
    }
  }

  readFrom(value: string): Cidr | undefined {
    let arr = value.split("/")
    if (arr.length != 2 || !isMask(arr[1]) || !isIpAddr(arr[0])) {
      return undefined
    } else {
      this.ip = arr[0]
      this.mask = arr[1]
      return this
    }
  }

  toString(): string {
    return this.ip + "/" + this.mask
  }

  checkValid(): boolean {
    return isMask(this.mask) && isIpAddr(this.ip)
  }

  bind(fieldName: string): Cidr {
    this.fieldName = fieldName
    return this
  }
}