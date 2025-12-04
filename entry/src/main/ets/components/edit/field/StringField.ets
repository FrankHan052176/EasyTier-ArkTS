import { NetworkConfig } from "../../../protobuf/api_manage";
import { ContentUtil } from "../../../ContentUtil";
import { getFieldI18Name } from "../FieldEdit";
import { AppManager, Spx2vp } from "../../../AppManager";
import { TertiaryButton } from "../../util/TextButton";
import { getHostname } from "../../../util/Conversion";

@Extend(TextInput)
function fieldTextInput(onChange:EditableTextOnChangeCallback, inputType: InputType, enterKeyType: EnterKeyType, id: string, submit: OnSubmitCallback) {
  .padding(0)
  .borderRadius(0)
  .onChange(onChange)
  .backgroundColor(Color.Transparent)
  .width('100%')
  .type(inputType)
  .enableAutoFill(inputType !== InputType.Normal)
  .enterKeyType(enterKeyType)
  .id(id)
  .onSubmit(submit)
}

@ComponentV2
export struct StringField {
  @Param @Require config: NetworkConfig;
  @Param @Require field: string;
  @Consumer("field_edit_enable") enable: boolean = true
  @Local value: string = this.config[ContentUtil.safeFieldName(this.field)] || "";
  @Local intensity: number = 0;
  controller: TextInputController = new TextInputController()
  @Local offsetX: number = 0;
  @Local isEdit: boolean = false;

  @Computed
  get hasTitle() {
    return ContentUtil.hasTag(this.field, "topFieldName")
  }

  @Computed
  get inputType() {
    if (ContentUtil.hasTag(this.field, "username")) {
      return InputType.USER_NAME
    }else if (ContentUtil.hasTag(this.field, "password")) {
      return InputType.Password
    }else {
      return InputType.Normal
    }
  }

  @Computed
  get enterKey() {
    if (ContentUtil.hasTag(this.field, "enter_next")) {
      return EnterKeyType.Next
    }else {
      return EnterKeyType.Done
    }
  }

  @Computed
  get fontColor() {
    return this.enable?$r("sys.color.font_primary"):$r("sys.color.font_tertiary")
  }

  @Computed
  get isUseHostname() {
    return ContentUtil.hasTag(this.field, "useHostname")
  }

  build() {
    Column() {
      if (this.hasTitle || this.isUseHostname) {
        Row() {
          Text(getFieldI18Name(this.field))
            .fontSize(16)
            .focusable(false)
          if (this.isUseHostname) {
            TertiaryButton({text: "使用设备名", fontSize: 10})
              .clickEffect({
                level: ClickEffectLevel.MIDDLE
              })
              .onClick(() => {
                AppManager.permission.requestDistributePerm(false).then(() => {
                  let value: string = getHostname()
                  this.value = value
                  this.config[ContentUtil.safeFieldName(this.field)] = value
                })
              })
          }
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
        .justifyContent(FlexAlign.SpaceBetween)
        .margin({bottom: 5})
        .focusable(false)
      }
      Row() {
        TextInput({text: this.value!!, controller: this.controller})
          .fieldTextInput((value) => {
            this.config[ContentUtil.safeFieldName(this.field)] = value
          }, this.inputType, this.enterKey, this.field, () => {
            if (this.field === "network_name") {
              this.getUIContext().getFocusController().requestFocus("network_secret");
            }
          })
          .fontColor(this.fontColor)
          .onEditChange((isEdit) => {
            this.isEdit = isEdit
          })
      }
      .borderWidth(2)
      .borderColor(this.isEdit?$r("sys.color.brand"):(this.enable?$r("sys.color.comp_background_secondary"):$r("sys.color.comp_background_tertiary")))
      .padding({left: 12, right: 12, top: 8, bottom: 8})
      .borderRadius(12)
      .animation({
        curve: Curve.Ease,
        duration: 300
      })
    }
    .width('100%')
  }
}