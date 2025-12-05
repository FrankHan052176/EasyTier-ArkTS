import { FieldValue } from "./Basic"
import { LengthMetrics } from "@kit.ArkUI"
import { AppManager, Svp2fp } from "../../AppManager"

export function isIpAddr(value: string): boolean {
  return RegExp("^(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$").test(value)
}

@Builder
export function IPBuilder(value: IP) {
  Row({space: 10}) {
    Row() {
      SymbolGlyph($r("sys.symbol.arrow_left_arrow_right_and_rectangle_portrait"))
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

export let EditValue_IP: IP | undefined
export function clearEditValue_IP() {
  EditValue_IP = undefined
}
export function setEditValue_IP(ip: IP) {
  EditValue_IP = ip
}

@ComponentV2
export struct IPEditor {
  @Local ip: boolean = false

  build() {
    Column() {
      Row() {
        TextInput({text: EditValue_IP!.ip})
          .underline()
          .width("90%")
          .onChange((value: string) => {
            if (isIpAddr(value)) {
              this.ip = false
              if (EditValue_IP) {
                EditValue_IP.ip = value
              }
            }else {
              this.ip = true
            }
          })
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
      Text(`
请设置虚拟IP，如10.0.0.2
      `)
        .width('100%')
        .fontSize(14)
        .fontColor($r("sys.color.font_secondary"))
        .textAlign(TextAlign.Center)
      Blank()
        .width('100%')
        .height(100)
    }
    .width('90%')
  }
}

@ObservedV2
export class IP implements FieldValue {
  @Trace ip: string = "10.0.0.1"
  fieldName: string | undefined
  @Monitor("ip")
  onChange(monitor: IMonitor) {
    if (this.checkValid()) {
      let config = AppManager.data.configUUIDMap.get(AppManager.data.editingInstance ?? "")
      if (!config) return
      if (!this.fieldName) return
      let arr = config[this.fieldName] as string[]
      let old = "" + monitor.value("ip")?.before ?? this.ip
      let index = arr.indexOf(old)
      if (index < 0) return
      arr[index] = this.toString()
    }
  }
  fromString(value: string): boolean {
    if (isIpAddr(value)) {
      this.ip = value
      return true
    }else {
      return false
    }
  }
  readFrom(value: string): IP | undefined {
    if (isIpAddr(value)) {
      this.ip = value
      return this
    }else {
      return undefined
    }
  }
  toString(): string {
    return this.ip
  }
  checkValid(): boolean {
    return isIpAddr(this.ip)
  }
  bind(fieldName: string): IP {
    this.fieldName = fieldName
    return this
  }
}