import { NetworkConfig } from "../../../protobuf/api_manage";
import { hdsEffect } from "@kit.UIDesignKit";
import { deviceInfo } from "@kit.BasicServicesKit";
import { uiAppearance } from "@kit.ArkUI";
import { ContentUtil } from "../../../ContentUtil";
import { getFieldI18Name } from "../FieldEdit";
import { AppManager, Spx2vp } from "../../../AppManager";
import { getHostname } from "../../../util/Conversion";
import { Logger } from "../../../util/Logger";

@Extend(TextInput)
function fieldTextInput(onChange:EditableTextOnChangeCallback, inputType: InputType, enterKeyType: EnterKeyType, id: string, submit: OnSubmitCallback) {
  .padding({top:8, bottom: 8, left: 12, right: 12})
  .borderWidth(0)
  .borderRadius(12)
  .onChange(onChange)
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
  @Local value: string = this.config[ContentUtil.safeFieldName(this.field)] || "";
  @Local intensity: number = 0;
  comp_height: number = 0;
  controller: TextInputController = new TextInputController()
  @Local offsetX: number = 0;
  @Local suggest: boolean = false;

  @Builder
  LightPoint() {
    Flex()
      .width(1)
      .height(1)
      .visualEffect(new hdsEffect.HdsEffectBuilder().pointLight({
        illuminatedType: hdsEffect.PointLightIlluminatedType.BORDER,
        options: {
          color: uiAppearance.getDarkMode() === 0?"#FFFFFF":"#0a59f7",
          intensity: this.intensity,
          height: this.comp_height*2
        }
      }).buildEffect())
      .animation({
        curve: Curve.Ease,
        duration: 300
      })
  }

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
  get hasSuggest() {
    return ContentUtil.hasTag(this.field, "suggest")
  }

  @Builder
  suggestion() {
    Text("替换设备名")
      .onClick(() => {
        Logger.debug("click")
        AppManager.permission.requestDistributePerm(true).then(() => {
          this.value = getHostname()
          this.config[ContentUtil.safeFieldName(this.field)] = this.value
        })
      })
      .padding(10)
  }

  build() {
    Column() {
      if (this.hasTitle) {
        Row() {
          Text(getFieldI18Name(this.field))
            .fontSize(18)
            .focusable(false)
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
        .justifyContent(FlexAlign.Start)
        .margin({bottom: 5})
        .focusable(false)
      }
      if (deviceInfo.sdkApiVersion >= 20) {
        Row() {
          TextInput({text: this.value!!, controller: this.controller})
            .fieldTextInput((value) => {
              this.config[ContentUtil.safeFieldName(this.field)] = value
            }, this.inputType, this.enterKey, this.field, () => {
              if (this.field === "networkName") {
                this.getUIContext().getFocusController().requestFocus("networkSecret");
              }
            })
            .overlay(this.LightPoint(),{
              align: Alignment.TopStart,
              offset: {
                y: this.comp_height/2,
                x: this.offsetX
              }
            })
            .onSecurityStateChange(() => {
              setTimeout(() => {
                this.offsetX = Spx2vp(this.controller.getCaretOffset().x)
              }, 10)
            })
            .onTextSelectionChange(() => {
              setTimeout(() => {
                this.offsetX = Spx2vp(this.controller.getCaretOffset().x)
              }, 10)
            })
            .onContentScroll(() => {
              setTimeout(() => {
                this.offsetX = Spx2vp(this.controller.getCaretOffset().x)
              }, 10)
            })
            .onEditChange((isEdit) => {
              this.intensity = isEdit?1:0
              if (this.hasSuggest) {
                this.suggest = isEdit
              }
            })
            .onAreaChange((_a,b) => {
              this.comp_height = b.height.valueOf() as number
            })
            .bindPopup(this.suggest, {
              builder: this.suggestion(),
              placement: Placement.Top,
              targetSpace: 10,
              enableArrow: false,
              onStateChange: (e) => {
                if (!e.isVisible) {
                  this.suggest = false
                }
              }
            })
        }
        .borderWidth(0)
        .borderRadius(12)
        .visualEffect(new hdsEffect.HdsEffectBuilder()
          .pointLight({
            illuminatedType: hdsEffect.PointLightIlluminatedType.BORDER
          }).buildEffect())
      }else {
        TextInput({text: this.value!!})
          .fieldTextInput((value) => {
            this.config[ContentUtil.safeFieldName(this.field)] = value
          }, this.inputType, this.enterKey, this.field, () => {
            if (this.field === "networkName") {
              this.getUIContext().getFocusController().requestFocus("networkSecret");
            }
          })
      }
    }
    .width('100%')
  }
}