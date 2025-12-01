import { EditableLeftIconType, EditableTitleBar, LengthMetrics } from "@kit.ArkUI"
import { AppManager } from "../../AppManager";
import { clearEditValue_Cidr, EditValue_Cidr } from "../../class/config/Cidr"
import { clearEditValue_IP, EditValue_IP } from "../../class/config/IP";
import { clearEditValue_NetworkName, EditValue_NetworkName } from "../../class/config/NetworkName";
import { clearEditValue_Url, EditValue_Url } from "../../class/config/Url";
import { EventHelper } from "../../util/EventHelper"

function clearEditValue(type: string) {
  switch (type) {
    case "route":
    case "cidr": {
      clearEditValue_Cidr()
      break;
    }
    case "mappedListener":
    case "listener":
    case "peer": {
      clearEditValue_Url()
      break;
    }
    case "ip": {
      clearEditValue_IP()
      break;
    }
    case "string": {
      clearEditValue_NetworkName()
      break;
    }
    case "port_forward": {
      // TODO 端口转发 清空临时变量
      break;
    }
  }
}

function confirmCheck(type: string): boolean {
  switch (type) {
    case "route":
    case "cidr": {
      return EditValue_Cidr?.checkValid() ?? false
    }
    case "mappedListener":
    case "listener":
    case "peer": {
      return EditValue_Url?.checkValid() ?? false
    }
    case "ip": {
      return EditValue_IP?.checkValid() ?? false
    }
    case "string": {
      return EditValue_NetworkName?.checkValid() ?? false
    }
    case "port_forward": {
      // TODO 端口转发 检查文本合法
      return false
    }
  }
  return false
}

function addValue(type: string) {
  switch (type) {
    case "route":
    case "cidr": {
      animateToImmediately({
        curve: Curve.Ease,
        duration: 300
      }, () => {
        AppManager.data.getDataSource(type).add(EditValue_Cidr!)
      })
      break;
    }
    case "mappedListener":
    case "listener":
    case "peer": {
      animateToImmediately({
        curve: Curve.Ease,
        duration: 300
      }, () => {
        AppManager.data.getDataSource(type).add(EditValue_Url!)
      })
      break;
    }
    case "ip": {
      animateToImmediately({
        curve: Curve.Ease,
        duration: 300
      }, () => {
        AppManager.data.getDataSource(type).add(EditValue_IP!)
      })
      break;
    }
    case "string": {
      animateToImmediately({
        curve: Curve.Ease,
        duration: 300
      }, () => {
        AppManager.data.getDataSource(type).add(EditValue_NetworkName!)
      })
      break;
    }
    case "port_forward": {
      // TODO 端口转发 新增配置
      break;
    }
  }
}

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