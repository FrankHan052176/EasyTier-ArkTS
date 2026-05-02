import { AppManager } from '../../../AppManager';
import { getFieldPathValue, setFieldPathValue, syncFieldPath } from '../../../ConfigSyncUtil';

@Extend(TextInput)
function fieldTextInput() {
  .padding(0)
  .borderRadius(0)
  .width(72)
  .type(InputType.Number)
  .maxLength(5)
  .backgroundColor(Color.Transparent)
  .textAlign(TextAlign.Center)
  .enableAutoFill(false)
}

@ComponentV2
export struct PortField {
  @Param @Require field: string;
  @Param fieldPath: string[] = [this.field]
  @Param @Require text: ResourceStr;
  @Consumer("field_edit_enable") enable: boolean = true
  @Local value: string = "" + (getFieldPathValue(this.config!, this.fieldPath) ?? 0);
  @Local isEdit: boolean = false;

  @Computed
  get config() {
    return AppManager.easytier.getEditingConfig()
  }

  @Computed
  get fontColor() {
    return this.enable ? $r("sys.color.font_primary") : $r("sys.color.font_tertiary")
  }

  insert(value: InsertValue): boolean {
    let newValue = this.value.substring(0, value.insertOffset)
      + value.insertValue
      + this.value.substring(value.insertOffset);
    let num = Number.parseInt(newValue)
    let result = num > 0 && num <= 65535
    return result
  }

  delete(value: DeleteValue): boolean {
    const start = value.direction === TextDeleteDirection.BACKWARD
      ? value.deleteOffset
      : value.deleteOffset - value.deleteValue.length;
    let newValue = this.value.substring(0, start) + this.value.substring(start + value.deleteValue.length);
    let num = Number.parseInt(newValue)
    let result = num > 0 && num <= 65535
    if (!result) {
      this.value = ""
    }
    return result
  }

  change(value: string) {
    this.value = value
    let num = Number.parseInt(value)
    setFieldPathValue(this.config!, this.fieldPath, Number.isNaN(num) ? 0 : num)
    syncFieldPath(this.config!.instance_id!, this.fieldPath, this.config!)
  }

  build() {
    Row() {
      Text(this.text)
        .focusable(false)
      Row() {
        TextInput({ text: this.value!! })
          .onWillInsert((data) => this.insert(data))
          .onWillDelete((data) => this.delete(data))
          .onChange((value) => this.change(value))
          .fieldTextInput()
          .onEditChange((isEdit) => {
            this.isEdit = isEdit
          })
          .fontColor(this.fontColor)
          .enabled(this.enable)
      }
      .borderWidth(2)
      .borderColor(this.isEdit ? $r("sys.color.brand") :
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
    }
    .alignItems(VerticalAlign.Center)
    .justifyContent(FlexAlign.SpaceBetween)
    .width('100%')
  }
}
