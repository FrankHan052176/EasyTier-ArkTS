import { hasFieldTag } from '../../../config/fields/ConfigFieldUi';
import { getFieldI18Name } from '../FieldLabel';
import { AppManager } from '../../../AppManager';
import { getFieldPathValue, setFieldPathValue, syncFieldPath } from '../../../ConfigSyncUtil';
import { TertiaryButton } from '../../util/TextButton';
import { getHostname } from '../../../util/Conversion';

@Extend(TextInput)
function fieldTextInput(onChange: EditableTextOnChangeCallback, inputType: InputType, enterKeyType: EnterKeyType,
  id: string, submit: OnSubmitCallback, unsafe: boolean, unlock: boolean) {
  .padding(0)
  .borderRadius(0)
  .onChange(onChange)
  .backgroundColor(Color.Transparent)
  .width('100%')
  .type(inputType)
  .enableAutoFill(!unsafe || unlock)
  .enterKeyType(enterKeyType)
  .id(id)
  .onSubmit(submit)
}

@ComponentV2
export struct StringField {
  @Param @Require field: string;
  @Param fieldPath: string[] = [this.field]
  @Local value: string = (getFieldPathValue(this.config!, this.fieldPath) as string) || "";
  @Consumer("field_edit_enable") enable: boolean = true
  @Local intensity: number = 0;
  @Local offsetX: number = 0;
  @Local isEdit: boolean = false;
  @Consumer("unsafe_status") unsafe: boolean = false
  @Consumer("lock_status") unlock: boolean = false
  private syncingFromConfig: boolean = false
  private syncResetTimer: number = -1
  private active: boolean = false

  @Computed
  get hasTopTitle() {
    return hasFieldTag(this.field, "topFieldName")
  }

  @Computed
  get hasLeftTitle() {
    return hasFieldTag(this.field, "leftFieldName")
  }

  @Computed
  get config() {
    return AppManager.easytier.getEditingConfig()
  }

  @Computed
  get inputType() {
    if (hasFieldTag(this.field, "username")) {
      return InputType.USER_NAME
    } else if (hasFieldTag(this.field, "password")) {
      return InputType.Password
    } else {
      return InputType.Normal
    }
  }

  @Computed
  get enterKey() {
    if (hasFieldTag(this.field, "enter_next")) {
      return EnterKeyType.Next
    } else {
      return EnterKeyType.Done
    }
  }

  @Computed
  get fontColor() {
    return this.enable ? $r("sys.color.font_primary") : $r("sys.color.font_tertiary")
  }

  @Computed
  get isUseHostname() {
    return hasFieldTag(this.field, "useHostname")
  }

  private updateFromConfig(): void {
    if (!this.isEdit) {
      const nextValue = (getFieldPathValue(this.config!, this.fieldPath) as string) || ""
      if (this.value !== nextValue) {
        this.syncingFromConfig = true
        this.value = nextValue
        if (this.syncResetTimer >= 0) {
          clearTimeout(this.syncResetTimer)
          this.syncResetTimer = -1
        }
        this.syncResetTimer = setTimeout(() => {
          this.syncResetTimer = -1
          this.syncingFromConfig = false
        }, 0)
      }
    }
  }

  aboutToAppear(): void {
    this.active = true
    this.updateFromConfig()
  }

  aboutToDisappear(): void {
    this.active = false
    if (this.syncResetTimer >= 0) {
      clearTimeout(this.syncResetTimer)
      this.syncResetTimer = -1
    }
    this.syncingFromConfig = false
    this.isEdit = false
    this.value = ''
  }

  build() {
    Row() {
      if (this.hasLeftTitle) {
        Text(getFieldI18Name(this.field))
          .fontSize(16)
          .focusable(false)
          .margin({ right: 15 })
      }
      Column() {
        if (this.hasTopTitle || this.isUseHostname) {
          Row() {
            Text(getFieldI18Name(this.field))
              .fontSize(16)
              .focusable(false)
            if (this.isUseHostname) {
              TertiaryButton({ text: "使用设备名", fontSize: 10 })
                .clickEffect({
                  level: ClickEffectLevel.MIDDLE
                })
                .onClick(() => {
                  AppManager.permission.requestDistributePerm(false).then(() => {
                    if (!this.active) {
                      return
                    }
                    let value: string = getHostname()
                    this.value = value
                    setFieldPathValue(this.config!, this.fieldPath, value)
                    syncFieldPath(this.config!.instance_id!, this.fieldPath, this.config!)
                  })
                })
            }
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)
          .justifyContent(FlexAlign.SpaceBetween)
          .margin({ bottom: 5 })
          .focusable(false)
        }
        Row() {
            TextInput({ text: $$this.value })
              .fieldTextInput((value) => {
                if (this.syncingFromConfig) {
                  return
                }
                this.value = value
                setFieldPathValue(this.config!, this.fieldPath, value)
                syncFieldPath(this.config!.instance_id!, this.fieldPath, this.config!)
              }, this.inputType, this.enterKey, this.field, () => {
              if (this.field === "network_name") {
                this.getUIContext().getFocusController().requestFocus("network_secret");
              }
            }, this.unsafe, this.unlock)
            .fontColor(this.fontColor)
            .onEditChange((isEdit) => {
              this.isEdit = isEdit
            })
            .width('100%')
        }
        .width('100%')
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
        .justifyContent(FlexAlign.SpaceBetween)
      }
      .layoutWeight(100)
    }
    .width('100%')
  }
}
