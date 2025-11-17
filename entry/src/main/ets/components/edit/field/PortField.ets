import { NetworkConfig } from "../../../protobuf/api_manage";
import { deviceInfo } from "@kit.BasicServicesKit";
import { hdsEffect } from "@kit.UIDesignKit";
import { ContentUtil } from "../../../ContentUtil";

@Extend(TextInput)
function fieldTextInput() {
  .padding({top:5, bottom: 5, left: 12, right: 12})
  .width(72)
  .type(InputType.Number)
  .maxLength(5)
  .borderWidth(0)
  .borderRadius(12)
  .textAlign(TextAlign.Center)
  .enableAutoFill(false)
}

@ComponentV2
export struct PortField {
  @Param @Require config: NetworkConfig;
  @Param @Require field: string;
  @Param @Require text: ResourceStr;
  @Local value: string = this.config[ContentUtil.safeFieldName(this.field)] || "";

  insert(value: InsertValue):boolean {
    let newValue = this.value.substring(0, value.insertOffset)
      + value.insertValue
      + this.value.substring(value.insertOffset);
    let num = Number.parseInt(newValue)
    let result = num > 0 && num <= 65535
    return result
  }

  delete(value: DeleteValue):boolean {
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
    let num = Number.parseInt(value)
    if (Number.isNaN(num)) {
      this.config[ContentUtil.safeFieldName(this.field)] = undefined
    }else {
      this.config[ContentUtil.safeFieldName(this.field)] = num
    }
  }

  build() {
    Row() {
      Text(this.text)
      if (deviceInfo.sdkApiVersion >= 20) {
        Row() {
          TextInput({text: this.value!!})
            .onWillInsert((data) => this.insert(data))
            .onWillDelete((data) => this.delete(data))
            .onChange((value) => this.change(value))
            .fieldTextInput()
        }
        .borderWidth(0)
        .borderRadius(12)
        .visualEffect(new hdsEffect.HdsEffectBuilder().pointLight({
          illuminatedType: hdsEffect.PointLightIlluminatedType.BORDER,
        }).buildEffect())
      }else {
        TextInput({text: this.value!!})
          .onWillInsert((data) => this.insert(data))
          .onWillDelete((data) => this.delete(data))
          .onChange((value) => this.change(value))
          .fieldTextInput()
      }
    }
    .alignItems(VerticalAlign.Center)
    .justifyContent(FlexAlign.SpaceBetween)
    .width('100%')
  }
}