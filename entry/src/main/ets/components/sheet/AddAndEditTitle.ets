import { EditableLeftIconType, EditableTitleBar, LengthMetrics } from "@kit.ArkUI"
import { AppManager } from "../../AppManager";
import { addValue, clearEditValue, confirmCheck } from "../../class/config/Basic";
import { EventHelper } from "../../util/EventHelper"

function getI18_FieldName(fieldName: string): string {
  try {
    return AppManager.content.context!.resourceManager.getStringSync($r('app.string.' + fieldName).id)
  } catch (error) {
    return ""
  }
}

@ComponentV2
export struct AddTitle {
  @Param @Require fieldName: string
  @Param @Require fieldType: string

  build() {
    EditableTitleBar({
      leftIconStyle: EditableLeftIconType.Cancel,
      title: $r("app.string.i18_add", getI18_FieldName(this.fieldName)),
      contentMargin: {
        start: LengthMetrics.vp(0),
        end: LengthMetrics.vp(0),
      },
      onCancel: () => {
        clearEditValue(this.fieldType)
        EventHelper.emitterPublish("edit_close_sheet")
      },
      onSave: () => {
        if (confirmCheck(this.fieldType)) {
          addValue(this.fieldType)
          clearEditValue(this.fieldType)
          EventHelper.emitterPublish("edit_close_sheet")
        }
      }
    })
  }
}

@ComponentV2
export struct EditTitle {
  @Param @Require fieldName: string
  @Param @Require fieldType: string

  build() {
    EditableTitleBar({
      leftIconStyle: EditableLeftIconType.Cancel,
      title: $r("app.string.i18_edit", getI18_FieldName(this.fieldName)),
      contentMargin: {
        start: LengthMetrics.vp(0),
        end: LengthMetrics.vp(0),
      },
      onCancel: () => {
        clearEditValue(this.fieldType)
        EventHelper.emitterPublish("edit_close_sheet")
      },
      onSave: () => {
        if (confirmCheck(this.fieldType)) {
          clearEditValue(this.fieldType)
          EventHelper.emitterPublish("edit_close_sheet")
        }
      }
    })
  }
}
