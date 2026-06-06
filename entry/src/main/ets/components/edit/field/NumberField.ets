import { hasFieldTag } from '../../../config/fields/ConfigFieldUi';
import { getFieldI18Name } from '../FieldEdit';
import { AppManager } from '../../../AppManager';
import { getFieldPathValue, setFieldPathValue, syncFieldPath } from '../../../ConfigSyncUtil';
import { getEditingConfigFieldRefreshEvent } from '../../../services/config/storage/StoredConfigService';
import { EventHelper } from '../../../util/EventHelper';

@Extend(TextInput)
function fieldTextInput() {
  .padding(0)
  .borderRadius(0)
  .width(72)
  .type(InputType.Number)
  .backgroundColor(Color.Transparent)
  .textAlign(TextAlign.Center)
  .enableAutoFill(false)
}

@ComponentV2
export struct NumberField {
  @Param @Require field: string;
  @Param fieldPath: string[] = [this.field]
  @Consumer("field_edit_enable") enable: boolean = true
  @Local value: string = "" + (getFieldPathValue(this.config!, this.fieldPath) ?? "");
  @Local intensity: number = 0;
  controller: TextInputController = new TextInputController()
  @Local offsetX: number = 0;
  @Local isEdit: boolean = false;
  private fieldRefreshEvent: string = ''
  private fieldRefreshCallback = () => {
    this.updateFromConfig()
  }

  @Computed
  get hasTitle() {
    return hasFieldTag(this.field, "topFieldName")
  }

  @Computed
  get config() {
    return AppManager.easytier.getEditingConfig()
  }

  @Computed
  get fontColor() {
    return this.enable ? $r("sys.color.font_primary") : $r("sys.color.font_tertiary")
  }

  private topLevelField(): string {
    return this.fieldPath.length > 0 ? this.fieldPath[0] : this.field
  }

  private updateFromConfig(): void {
    if (!this.isEdit) {
      this.value = "" + (getFieldPathValue(this.config!, this.fieldPath) ?? "")
    }
  }

  aboutToAppear(): void {
    this.updateFromConfig()
    this.fieldRefreshEvent = getEditingConfigFieldRefreshEvent(this.topLevelField())
    EventHelper.emitterListener(this.fieldRefreshEvent, this.fieldRefreshCallback)
  }

  aboutToDisappear(): void {
    if (this.fieldRefreshEvent.length > 0) {
      EventHelper.emitterOff(this.fieldRefreshEvent, this.fieldRefreshCallback)
      this.fieldRefreshEvent = ''
    }
  }

  build() {
    Row() {
      Text(getFieldI18Name(this.field))
        .focusable(false)
      Row() {
        TextInput({ text: this.value!!, controller: this.controller })
          .fieldTextInput()
          .onChange((value) => {
            if (value.length == 0) {
              setFieldPathValue(this.config!, this.fieldPath, undefined)
              syncFieldPath(this.config!.instance_id!, this.fieldPath, this.config!)
            }else {
              let num = Number.parseInt(value)
              this.value = value
              setFieldPathValue(this.config!, this.fieldPath, Number.isNaN(num) ? 0 : num)
              syncFieldPath(this.config!.instance_id!, this.fieldPath, this.config!)
            }
          })
          .fontColor(this.fontColor)
          .onEditChange((isEdit) => {
            this.isEdit = isEdit
          })
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
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .justifyContent(FlexAlign.SpaceBetween)
  }
}
