import { EditableLeftIconType, EditableTitleBar, LengthMetrics } from "@kit.ArkUI"
import { AppManager } from "../../AppManager"
import { EventHelper } from "../../util/EventHelper"
import { buffer } from "@kit.ArkTS"

@ComponentV2
export struct Rename_Title {
  build() {
    EditableTitleBar({
      leftIconStyle: EditableLeftIconType.Back,
      title: '重命名',
      contentMargin: {
        start: LengthMetrics.vp(0),
        end: LengthMetrics.vp(0),
      },
      isSaveIconRequired: false,
      onCancel: () => {
        EventHelper.emitterPublish("edit_close_sheet")
      }
    })
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

@ComponentV2
export struct Rename_Content {
  @Computed
  get instanceName() {
    return AppManager.data.configUUIDNameMap.get(AppManager.data.editingInstance ?? "") ?? "N/A"
  }

  build() {
    Column() {
      Row() {
        TextInput({text: this.instanceName})
          .underline()
          .width('80%')
          .onChange((value: string) => {
            if (value.length > 0) {
              if (AppManager.data.editingInstance) {
                AppManager.data.configNameUUIDMap.delete(this.instanceName)
                AppManager.data.configNameUUIDMap.set(value, AppManager.data.editingInstance)
                AppManager.data.configUUIDNameMap.set(AppManager.data.editingInstance, value)
                AppManager.preference.configIDPreferences?.putSync(AppManager.data.editingInstance, new Uint8Array(buffer.from(value, 'utf-8').buffer))
                AppManager.preference.configIDPreferences?.flushSync()
              }
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