import { FieldValue } from './Basic'
import { LengthMetrics } from '@kit.ArkUI'
import { AppManager, Svp2fp } from '../../AppManager'
import { ConfigJson } from '../../SchemaConfig'

export function isIpAddr(value: string): boolean {
  return RegExp("^(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$")
    .test(value)
}

@Builder
export function IPBuilder(value: IP) {
  Row({ space: 10 }) {
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
      Column({ space: 8 }) {
        Text("虚拟 IP 地址")
          .fontSize(14)
          .fontColor($r("sys.color.font_secondary"))
          .width('100%')

        TextInput({ text: EditValue_IP!.ip, placeholder: "请输入 IP 地址" })
          .width('100%')
          .backgroundColor($r("sys.color.comp_background_tertiary"))
          .borderRadius(8)
          .padding(10)
          .onChange((value: string) => {
            if (isIpAddr(value)) {
              this.ip = false
              if (EditValue_IP) {
                EditValue_IP.ip = value
              }
            } else {
              this.ip = true
            }
          })
      }
      .width('100%')
      .padding(16)
      .backgroundColor($r("sys.color.comp_background_primary"))
      .borderRadius(16)

      Row() {
        SymbolGlyph($r('sys.symbol.info_circle'))
          .fontSize(16)
          .fontColor([$r('sys.color.font_secondary')])
          .margin({ right: 8 })
        Text("请设置虚拟 IP，如 10.0.0.2")
          .fontSize(12)
          .fontColor($r('sys.color.font_secondary'))
      }
      .width('100%')
      .padding({ top: 12, left: 16, right: 16 })
      .alignItems(VerticalAlign.Top)

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
      let config: ConfigJson = AppManager.easytier.getEditingConfig()
      if (!config) {
        return
      }
      if (!this.fieldName) {
        return
      }
      let arr = config[this.fieldName] as string[]
      let old = "" + (monitor.value("ip")?.before ?? this.ip)
      let index = arr.indexOf(old)
      if (index < 0) {
        return
      }
      arr[index] = this.toString()
    }
  }

  fromString(value: string): boolean {
    value = value.replace(/['"]/g, '')
    if (isIpAddr(value)) {
      this.ip = value
      return true
    } else {
      return false
    }
  }

  readFrom(value: string): IP | undefined {
    value = value.replace(/['"]/g, '')
    if (isIpAddr(value)) {
      this.ip = value
      return this
    } else {
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
