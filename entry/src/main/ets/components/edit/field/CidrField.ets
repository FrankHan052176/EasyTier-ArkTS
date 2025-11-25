import { ContentUtil } from '../../../ContentUtil';
import { hdsEffect } from '@kit.UIDesignKit';
import { NetworkConfig } from '../../../protobuf/api_manage';
import { uiAppearance } from '@kit.ArkUI';
import { deviceInfo } from '@kit.BasicServicesKit';
import { Spx2vp, Svp2fp } from '../../../AppManager';

@Extend(TextInput)
function fieldTextInput(onChange:EditableTextOnChangeCallback, editChange: OnSubmitCallback, ip: boolean, field: string) {
  .padding({top:5, bottom: 5, left: 12, right: 12})
  .borderWidth(0)
  .borderRadius(12)
  .onChange(onChange)
  .textAlign(TextAlign.Center)
  .width('100%')
  .enableAutoFill(false)
  .enterKeyType(ip?EnterKeyType.Next:EnterKeyType.Done)
  .id(field+(ip?"ip":"mask"))
  .onSubmit(editChange)
  .type(ip?InputType.Normal:InputType.Number)
  .maxLength(ip?Number.MAX_VALUE:2)
}

@ComponentV2
export  struct CidrField {
  @Param @Require config: NetworkConfig;
  @Param @Require field: string;
  @Param @Require text: ResourceStr;
  @Local value_ip: string = this.config[ContentUtil.safeFieldName(this.ipField)] || "";
  @Local value_mask: string = this.config[ContentUtil.safeFieldName(this.maskField)] || "";
  @Local intensity_ip: number = 0;
  @Local intensity_mask: number = 0;
  controller_ip: TextInputController = new TextInputController()
  controller_mask: TextInputController = new TextInputController()
  @Local offsetX_ip: number = 0
  @Local offsetX_mask: number = 0

  @Computed
  get ipField() {
    return ContentUtil.combinedField[this.field][0]
  }

  @Computed
  get maskField() {
    return ContentUtil.combinedField[this.field][1]
  }

  @Builder
  LightPoint(ip: boolean) {
    Flex()
      .width(1)
      .height(1)
      .visualEffect(new hdsEffect.HdsEffectBuilder().pointLight({
        illuminatedType: hdsEffect.PointLightIlluminatedType.BORDER,
        options: {
          color: uiAppearance.getDarkMode() === 0?"#FFFFFF":"#0a59f7",
          intensity: ip?this.intensity_ip:this.intensity_mask,
          height: 80
        }
      }).buildEffect())
      .animation({
        curve: Curve.Ease,
        duration: 300
      })
  }

  build() {
    Row() {
      Text(this.text)
        .margin({right: 5})
      if (deviceInfo.sdkApiVersion >= 20) {
        Row() {
          Row() {
            TextInput({text: this.value_ip!!, controller: this.controller_ip})
              .fieldTextInput((value) => {
                this.config[ContentUtil.safeFieldName(this.ipField)] = value
              }, () => {
                this.getUIContext().getFocusController().requestFocus(this.field+"mask");
              }, true, this.field)
              .overlay(this.LightPoint(true),{
                align: Alignment.Start,
                offset: {
                  x: this.offsetX_ip
                }
              })
              .onSecurityStateChange(() => {
                setTimeout(() => {
                  if (this.controller_ip.getCaretOffset() !== undefined) this.offsetX_ip = Spx2vp(this.controller_ip.getCaretOffset().x)
                }, 10)
              })
              .onTextSelectionChange(() => {
                setTimeout(() => {
                  if (this.controller_ip.getCaretOffset() !== undefined) this.offsetX_ip = Spx2vp(this.controller_ip.getCaretOffset().x)
                }, 10)
              })
              .onContentScroll(() => {
                setTimeout(() => {
                  if (this.controller_ip.getCaretOffset() !== undefined) this.offsetX_ip = Spx2vp(this.controller_ip.getCaretOffset().x)
                }, 10)
              })
              .onEditChange((isEdit) => {
                this.intensity_ip = isEdit?1:0
              })
          }
          .visualEffect(new hdsEffect.HdsEffectBuilder().pointLight({
            illuminatedType: hdsEffect.PointLightIlluminatedType.BORDER
          }).buildEffect())
          .borderRadius(12)
          .layoutWeight(100)
          Text("/")
            .fontWeight(FontWeight.Lighter)
            .fontSize(Svp2fp(40)-5)
            .margin({left: 5, right: 5})
          Row() {
            TextInput({text: this.value_mask!!, controller: this.controller_mask})
              .fieldTextInput((value) => {
                this.config[ContentUtil.safeFieldName(this.maskField)] = value
              }, () => {}, false, this.field)
              .overlay(this.LightPoint(false),{
                align: Alignment.Start,
                offset: {
                  x: this.offsetX_mask
                }
              })
              .onSecurityStateChange(() => {
                setTimeout(() => {
                  if (this.controller_mask.getCaretOffset() !== undefined) this.offsetX_mask = Spx2vp(this.controller_mask.getCaretOffset().x)
                }, 10)
              })
              .onTextSelectionChange(() => {
                setTimeout(() => {
                  if (this.controller_mask.getCaretOffset() !== undefined) this.offsetX_mask = Spx2vp(this.controller_mask.getCaretOffset().x)
                }, 10)
              })
              .onContentScroll(() => {
                setTimeout(() => {
                  if (this.controller_mask.getCaretOffset() !== undefined) this.offsetX_mask = Spx2vp(this.controller_mask.getCaretOffset().x)
                }, 10)
              })
              .onEditChange((isEdit) => {
                this.intensity_mask = isEdit?1:0
              })
          }.visualEffect(new hdsEffect.HdsEffectBuilder().pointLight({
            illuminatedType: hdsEffect.PointLightIlluminatedType.BORDER
          }).buildEffect())
          .borderRadius(12)
          .width(44)
        }
        .borderWidth(0)
        .borderRadius(12)
        .layoutWeight(100)
      }else {
        Row() {
          TextInput({text: this.value_ip!!})
            .fieldTextInput((value) => {
              this.config[ContentUtil.safeFieldName(this.ipField)] = value
            }, () => {
              this.getUIContext().getFocusController().requestFocus(this.field+"mask");
            }, true, this.field)
            .layoutWeight(100)
          TextInput({text: this.value_mask!!})
            .fieldTextInput((value) => {
              this.config[ContentUtil.safeFieldName(this.maskField)] = value
            }, () => {}, false, this.field)
            .width(44)
        }
        .borderWidth(0)
        .borderRadius(12)
        .layoutWeight(100)
      }
    }
  }
}