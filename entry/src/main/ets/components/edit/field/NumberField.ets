import { ContentUtil } from '../../../ContentUtil';
import { getFieldI18Name } from '../FieldEdit';
import { AppManager } from '../../../AppManager';

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
export struct NumberField {
  @Param @Require field: string;
  @Consumer("field_edit_enable") enable: boolean = true
  @Local value: string = "" + (this.config![this.field] ?? "");
  @Local intensity: number = 0;
  controller: TextInputController = new TextInputController()
  @Local offsetX: number = 0;
  @Local isEdit: boolean = false;

  @Computed
  get hasTitle() {
    return ContentUtil.hasTag(this.field, "topFieldName")
  }

  @Computed
  get config() {
    return AppManager.easytier.getEditingConfig()
  }

  @Computed
  get preference() {
    return AppManager.preference.configPreferences.get(AppManager.uiState.editingInstance ?? "")
  }

  @Computed
  get fontColor() {
    return this.enable ? $r("sys.color.font_primary") : $r("sys.color.font_tertiary")
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
              this.config![this.field] = undefined
              this.preference?.deleteSync(this.field)
              this.preference?.flushSync()
            }else {
              let num = Number.parseInt(value)
              this.config![this.field] = Number.isNaN(num) ? 0 : num
              this.preference?.putSync(this.field, this.config![this.field])
              this.preference?.flushSync()
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