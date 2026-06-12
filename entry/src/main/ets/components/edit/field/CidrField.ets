import { AppManager } from '../../../AppManager';
import { hasFieldTag } from '../../../config/fields/ConfigFieldUi';
import { getFieldPathValue, setFieldPathValue, syncFieldPath } from '../../../ConfigSyncUtil';
import { getCombinedConfigChildren } from '../../../config/schema/SchemaLayout';

@Extend(TextInput)
function fieldTextInput(onChange: EditableTextOnChangeCallback, editChange: OnSubmitCallback, ip: boolean,
  field: string) {
  .backgroundColor(Color.Transparent)
  .borderRadius(0)
  .padding({
    top: 0,
    bottom: 0,
    left: 0,
    right: 0
  })
  .onChange(onChange)
  .textAlign(TextAlign.Start)
  .enableAutoFill(false)
  .enterKeyType(ip ? EnterKeyType.Next : EnterKeyType.Done)
  .id(field + (ip ? "ip" : "mask"))
  .onSubmit(editChange)
  .type(ip ? InputType.Normal : InputType.Number)
  .maxLength(ip ? Number.MAX_VALUE : 2)
}

@ComponentV2
export struct CidrField {
  @Param @Require field: string;
  @Param fieldPath: string[] = []
  @Param @Require text: ResourceStr;
  @Local value_ip: string = (getFieldPathValue(this.config!, this.ipFieldPath) as string) || "";
  @Local value_mask: string = "" + (getFieldPathValue(this.config!, this.maskFieldPath) ?? 24);
  @Local editIP: boolean = false
  @Local editMask: boolean = false
  @Consumer("field_edit_enable") enable: boolean = true

  @Computed
  get config() {
    return AppManager.easytier.getEditingConfig()
  }

  @Computed
  get ipField() {
    return getCombinedConfigChildren(this.field)[0]
  }

  @Computed
  get maskField() {
    return getCombinedConfigChildren(this.field)[1]
  }

  @Computed
  get ipFieldPath() {
    return [...this.fieldPath.slice(0, this.fieldPath.length - 1), this.ipField]
  }

  @Computed
  get maskFieldPath() {
    return [...this.fieldPath.slice(0, this.fieldPath.length - 1), this.maskField]
  }

  @Computed
  get borderWid() {
    return this.enable ? 2 : 0
  }

  @Computed
  get fontColor() {
    return this.enable ? $r("sys.color.font_primary") : $r("sys.color.font_tertiary")
  }

  @Computed
  get insideName() {
    return hasFieldTag(this.field, "insideName")
  }

  @Computed
  get outsideName() {
    return hasFieldTag(this.field, "outsideName")
  }

  private updateIpFromConfig(): void {
    if (!this.editIP) {
      this.value_ip = (getFieldPathValue(this.config!, this.ipFieldPath) as string) || ""
    }
  }

  private updateMaskFromConfig(): void {
    if (!this.editMask) {
      this.value_mask = "" + (getFieldPathValue(this.config!, this.maskFieldPath) ?? 24)
    }
  }

  aboutToAppear(): void {
    this.updateIpFromConfig()
    this.updateMaskFromConfig()
  }

  aboutToDisappear(): void {
    this.editIP = false
    this.editMask = false
    this.value_ip = ''
    this.value_mask = ''
  }

  build() {
    Row() {
      if (this.outsideName) {
        Text(this.text)
          .margin({ right: 10 })
          .fontColor($r("sys.color.font_primary"))
      }
      Row() {
        if (this.insideName) {
          Text(this.text)
            .margin({ right: 10 })
            .fontColor(this.fontColor)
        }
        Row() {
          TextInput({ text: this.value_ip!! })
            .fieldTextInput((value) => {
              this.value_ip = value
              setFieldPathValue(this.config!, this.ipFieldPath, value)
            }, () => {
              syncFieldPath(this.config!.instance_id!, this.ipFieldPath, this.config!)
              this.getUIContext().getFocusController().requestFocus(this.field + "mask");
            }, true, this.field)
            .layoutWeight(100)
            .onEditChange((isEdit) => {
              const wasEdit = this.editIP
              this.editIP = isEdit
              if (wasEdit && !isEdit) {
                syncFieldPath(this.config!.instance_id!, this.ipFieldPath, this.config!)
              }
            })
            .fontColor(this.fontColor)
            .enabled(this.enable)
          Text("/")
            .margin({ left: 5, right: 5 })
            .fontColor(this.fontColor)
          TextInput({ text: this.value_mask!! })
            .fieldTextInput((value) => {
              this.value_mask = value
              let num = Number.parseInt(value)
              setFieldPathValue(this.config!, this.maskFieldPath, Number.isNaN(num) ? 0 : num)
            }, () => {
              syncFieldPath(this.config!.instance_id!, this.maskFieldPath, this.config!)
            }, false, this.field)
            .width(30)
            .onEditChange((isEdit) => {
              const wasEdit = this.editMask
              this.editMask = isEdit
              if (wasEdit && !isEdit) {
                syncFieldPath(this.config!.instance_id!, this.maskFieldPath, this.config!)
              }
            })
            .fontColor(this.fontColor)
            .enabled(this.enable)
        }
        .layoutWeight(100)
      }
      .borderWidth(2)
      .borderColor((this.editIP || this.editMask) ? $r("sys.color.brand") :
        (this.enable ? $r("sys.color.comp_background_secondary") : $r("sys.color.comp_background_tertiary")))
      .padding({
        left: 12,
        right: 12,
        top: 8,
        bottom: 8
      })
      .borderRadius(12)
      .animation({
        curve: Curve.Ease,
        duration: 300
      })
      .layoutWeight(100)
    }
    .width('100%')
  }
}
