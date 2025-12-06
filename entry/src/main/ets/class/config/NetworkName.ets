import { FieldValue } from "./Basic"
import { LengthMetrics } from "@kit.ArkUI"
import { AppManager, Svp2fp } from "../../AppManager"

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

export let EditValue_NetworkName: NetworkName | undefined
export function clearEditValue_NetworkName() {
  EditValue_NetworkName = undefined
}
export function setEditValue_NetworkName(value: NetworkName) {
  EditValue_NetworkName = value
}

@ComponentV2
export struct NetworkNameEditor {
  @Local name: boolean = false

  build() {
    Column() {
      Row() {
        TextInput({text: EditValue_NetworkName!.name})
          .underline()
          .width('80%')
          .onChange((value: string) => {
            if (value.length > 0) {
              this.name = false
              if (EditValue_NetworkName) {
                EditValue_NetworkName.name = value
              }
            }else {
              this.name = true
            }
          })
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
      Text(`
请设置网络名
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
export function NetworkNameBuilder(value: NetworkName) {
  Row({space: 10}) {
    Row() {
      SymbolGlyph($r("sys.symbol.checkmark_shield"))
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
export class NetworkName implements FieldValue {
  @Trace name: string = "easytier"
  fieldName: string | undefined
  @Monitor("name")
  onChange(monitor: IMonitor) {
    if (this.checkValid()) {
      let config = AppManager.data.configUUIDMap.get(AppManager.data.editingInstance ?? "")
      if (!config) return
      if (!this.fieldName) return
      let arr = config[this.fieldName] as string[]
      let old = "" + monitor.value("name")?.before ?? this.name
      let index = arr.indexOf(old)
      if (index < 0) return
      arr[index] = this.toString()
    }
  }
  fromString(value: string): boolean {
    this.name = value
    return true
  }
  readFrom(value: string): NetworkName | undefined {
    this.name = value
    return this
  }
  toString(): string {
    return this.name
  }
  checkValid(): boolean {
    return this.name.length > 0
  }
  bind(fieldName: string): NetworkName {
    this.fieldName = fieldName
    return this
  }
}