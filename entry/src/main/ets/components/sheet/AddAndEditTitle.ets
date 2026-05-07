import { EditableLeftIconType, EditableTitleBar, LengthMetrics } from '@kit.ArkUI';
import { AppManager } from '../../AppManager';
import { addValue, clearEditValue, commitEditValue, confirmCheck } from '../../class/config/Basic';
import { syncTopLevelField } from '../../ConfigSyncUtil';
import { ConfigJson } from '../../config/schema/SchemaConfig';
import { EventHelper } from '../../util/EventHelper';
import { Logger } from '../../shared/logging/Logger';
import { GlobalConfigSuggestions } from '../edit/GlobalConfigSuggestion';

function getI18_FieldName(fieldName: string): string {
  try {
    return AppManager.content.context!.resourceManager.getStringSync($r('app.string.' + fieldName).id)
  } catch (error) {
    return ""
  }
}

@Builder
export function GlobalConfig(field: string, type: string, width: number) {
  GlobalConfigSuggestions({ field: field, type: type, comp_width: width })
}

@ComponentV2
export struct AddTitle {
  @Param @Require fieldName: string
  @Param @Require fieldType: string
  @Local popup: boolean = false
  @Local sugWidth: number = 344

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
        builder: GlobalConfig(this.fieldName, this.fieldType, this.sugWidth),
        placement: Placement.Top,
        autoCancel: true,
        enableArrow: false,
        offset: {
          y: -20
        },
        mask: false,
        radius: 18
      })
      .onAreaChange((a,b) => {
        this.sugWidth = b.width.valueOf() as number
        if (!this.popup) {
          this.popup = true
        }
      })
  }
}

@ComponentV2
export struct EditTitle {
  @Param @Require fieldName: string
  @Param @Require fieldType: string
  @Local popup: boolean = false
  @Local sugWidth: number = 344

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
        if (confirmCheck(this.fieldType)) {
          const config: ConfigJson | undefined = AppManager.easytier.getEditingConfig()
          const configId: string | undefined = config?.instance_id
          if (config && configId) {
            Logger.debug(`EditTitle save field=${this.fieldName} type=${this.fieldType} configId=${configId}`, 'AddAndEditTitle')
            commitEditValue(config, this.fieldName, this.fieldType)
            syncTopLevelField(configId, this.fieldName, config)
          }
        } else {
          Logger.debug(`EditTitle skip save invalid field=${this.fieldName} type=${this.fieldType}`, 'AddAndEditTitle')
        }
        clearEditValue(this.fieldType)
        EventHelper.emitterPublish("edit_close_sheet")
        EventHelper.emitterPublish("edit_refresh_" + this.fieldName)
        AppManager.data.getDataSource(this.fieldType).update()
      }
    })
      .bindPopup(this.popup, {
        builder: GlobalConfig(this.fieldName, this.fieldType, this.sugWidth),
        placement: Placement.Top,
        autoCancel: true,
        enableArrow: false,
        offset: {
          y: -20
        },
        mask: false,
        radius: 18
      })
      .onAreaChange((a,b) => {
        this.sugWidth = b.width.valueOf() as number
        if (!this.popup) {
          this.popup = true
        }
      })
  }
}
