import { EditableLeftIconType, EditableTitleBar, LengthMetrics } from '@kit.ArkUI';
import { AppManager } from '../../AppManager';
import { addValue, clearEditValue, confirmCheck } from '../../class/config/Basic';
import { EventHelper } from '../../util/EventHelper';
import { GlobalConfigSuggestions } from '../edit/GlobalConfigSuggestion';

function getI18_FieldName(fieldName: string): string {
  try {
    return AppManager.content.context!.resourceManager.getStringSync($r('app.string.' + fieldName).id)
  } catch (error) {
    return ""
  }
}

@Builder
export function GlobalConfig(field: string, type: string) {
  GlobalConfigSuggestions({ field: field, type: type })
}

@ComponentV2
export struct AddTitle {
  @Param @Require fieldName: string
  @Param @Require fieldType: string
  @Local popup: boolean = true

  aboutToAppear(): void {
    EventHelper.commonListener("edit_will_dismiss", () => {
      this.popup = false
    })
  }

  build() {
    EditableTitleBar({
      leftIconStyle: EditableLeftIconType.Cancel,
      title: $r("app.string.i18_add", getI18_FieldName(this.fieldName)),
      contentMargin: {
        start: LengthMetrics.vp(0),
        end: LengthMetrics.vp(0),
      },
      onCancel: () => {
        this.popup = false
        clearEditValue(this.fieldType)
        EventHelper.emitterPublish("edit_close_sheet")
      },
      onSave: () => {
        if (confirmCheck(this.fieldType)) {
          this.popup = false
          addValue(this.fieldName, this.fieldType)
          clearEditValue(this.fieldType)
          EventHelper.emitterPublish("edit_refresh_" + this.fieldName)
          EventHelper.emitterPublish("edit_close_sheet")
        }
      }
    })
      .bindPopup(this.popup, {
        builder: GlobalConfig(this.fieldName, this.fieldType),
        placement: Placement.Top,
        autoCancel: true,
        enableArrow: false,
        offset: {
          y: -20
        },
        mask: false,
        radius: 18
      })
  }
}

@ComponentV2
export struct EditTitle {
  @Param @Require fieldName: string
  @Param @Require fieldType: string
  @Local popup: boolean = true

  build() {
    EditableTitleBar({
      leftIconStyle: EditableLeftIconType.Back,
      title: $r("app.string.i18_edit", getI18_FieldName(this.fieldName)),
      contentMargin: {
        start: LengthMetrics.vp(0),
        end: LengthMetrics.vp(0),
      },
      isSaveIconRequired: false,
      onCancel: () => {
        this.popup = false
        clearEditValue(this.fieldType)
        EventHelper.emitterPublish("edit_close_sheet")
        EventHelper.emitterPublish("edit_refresh_" + this.fieldName)
        AppManager.data.getDataSource(this.fieldType).update()
      }
    })
      .bindPopup(this.popup, {
        builder: GlobalConfig(this.fieldName, this.fieldType),
        placement: Placement.Top,
        autoCancel: true,
        enableArrow: false,
        offset: {
          y: -20
        },
        mask: false,
        radius: 18
      })
  }
}
