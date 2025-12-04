import { ContentUtil } from '../../../ContentUtil';
import { NetworkConfig } from '../../../protobuf/api_manage';
import { Logger } from '../../../util/Logger';

@Extend(TextInput)
function fieldTextInput(onChange:EditableTextOnChangeCallback, editChange: OnSubmitCallback, ip: boolean, field: string) {
  .backgroundColor(Color.Transparent)
  .borderRadius(0)
  .padding({top:0, bottom: 0, left: 0, right: 0})
  .onChange(onChange)
  .textAlign(TextAlign.Start)
  .enableAutoFill(false)
  .enterKeyType(ip?EnterKeyType.Next:EnterKeyType.Done)
  .id(field+(ip?"ip":"mask"))
  .onSubmit(editChange)
  .type(ip?InputType.Normal:InputType.Number)
  .maxLength(ip?Number.MAX_VALUE:2)
}

@ComponentV2
export struct CidrField {
  @Param @Require config: NetworkConfig;
  @Param @Require field: string;
  @Param @Require text: ResourceStr;
  @Local value_ip: string = this.config[ContentUtil.safeFieldName(this.ipField)] || "";
  @Local value_mask: string = ""+(this.config[ContentUtil.safeFieldName(this.maskField)] || 24);
  @Local editIP: boolean = false
  @Local editMask: boolean = false
  @Consumer("field_edit_enable") enable: boolean = true

  @Monitor("enable")
  onChange() {
    Logger.debug("change to "+this.enable)
  }

  @Computed
  get ipField() {
    return ContentUtil.combinedField[this.field][0]
  }

  @Computed
  get maskField() {
    return ContentUtil.combinedField[this.field][1]
  }

  @Computed
  get borderWid() {
    return this.enable?2:0
  }

  @Computed
  get fontColor() {
    return this.enable?$r("sys.color.font_primary"):$r("sys.color.font_tertiary")
  }

  @Computed
  get insideName() {
    return ContentUtil.hasTag(this.field, "insideName")
  }

  @Computed
  get outsideName() {
    return ContentUtil.hasTag(this.field, "outsideName")
  }

  build() {
    Row() {
      if (this.outsideName) {
        Text(this.text)
          .margin({right: 10})
          .fontColor($r("sys.color.font_primary"))
      }
      Row() {
        if (this.insideName) {
          Text(this.text)
            .margin({right: 10})
            .fontColor(this.fontColor)
        }
        Row() {
          TextInput({text: this.value_ip!!})
            .fieldTextInput((value) => {
              this.config[ContentUtil.safeFieldName(this.ipField)] = value
            }, () => {
              this.getUIContext().getFocusController().requestFocus(this.field+"mask");
            }, true, this.field)
            .layoutWeight(100)
            .onEditChange((isEdit) => {
              this.editIP = isEdit
            })
            .fontColor(this.fontColor)
          Text("/")
            .margin({left: 5, right: 5})
            .fontColor(this.fontColor)
          TextInput({text: this.value_mask!!})
            .fieldTextInput((value) => {
              this.config[ContentUtil.safeFieldName(this.maskField)] = Number.parseInt(value)
            }, () => {}, false, this.field)
            .width(30)
            .onEditChange((isEdit) => {
              this.editMask = isEdit
            })
            .fontColor(this.fontColor)
        }
        .layoutWeight(100)
      }
      .borderWidth(2)
      .borderColor((this.editIP || this.editMask)?$r("sys.color.brand"):(this.enable?$r("sys.color.comp_background_secondary"):$r("sys.color.comp_background_tertiary")))
      .padding({left: 12, right: 12, top: 8, bottom: 8})
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