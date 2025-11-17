import { deviceInfo } from "@kit.BasicServicesKit";
import { NetworkConfig } from "../../../protobuf/api_manage";
import { lane } from "../../../util/Conversion";
import { hdsEffect } from "@kit.UIDesignKit";
import { curves, uiAppearance } from "@kit.ArkUI";
import { ContentUtil } from "../../../ContentUtil";

@Extend(Button)
function ButtonLightEffect() {
  .visualEffect(new hdsEffect.HdsEffectBuilder().pointLight({
    illuminatedType: hdsEffect.PointLightIlluminatedType.BORDER,
  }).buildEffect())
}

@ComponentV2
export struct BoolField {
  @Param @Require config: NetworkConfig
  @Param @Require field: string
  @Consumer('field_width') field_width: number = 0
  @Param text: ResourceStr = $r("app.string.i18_enable");
  @Param bind: boolean = true;
  @Event $bind: (val: boolean) => void = (val: boolean) => {};
  @Local button: boolean = true;
  @Local intensity: number = 1;

  aboutToAppear(): void {
    this.button = this.config[ContentUtil.safeFieldName(this.field)] || false
    this.intensity = this.button?1:0
    this.$bind(this.button)
  }

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
          height: lane(1)*1.2,
          bloom: uiAppearance.getDarkMode() === 0?1:0
        }
      }).buildEffect())
      .animation({
        curve: Curve.Ease,
        duration: 300
      })
  }

  @Styles
  booleanButton() {
    .height(34)
    .borderRadius(12)
    .width((this.field_width-10)/2-1)
    .padding({top: 4, bottom: 4, left: 15, right: 15})
    .clickEffect({
      level: ClickEffectLevel.LIGHT
    })
    .onClick(() => {
      animateToImmediately({
        curve: Curve.FastOutSlowIn,
        duration: 300
      }, () => {
        this.button = !this.button
        this.config[ContentUtil.safeFieldName(this.field)] = this.button
      })
      animateToImmediately({
        curve: curves.springMotion(0.4, 0.7),
        duration: 300
      }, () => {
        this.$bind(this.button)
      })
      this.intensity = this.button?1:0
    })
  }

  build() {
    if (deviceInfo.sdkApiVersion >= 20) {
      Button(this.text, {
        type: ButtonType.Normal,
        buttonStyle: this.button?ButtonStyleMode.EMPHASIZED:ButtonStyleMode.NORMAL,
        role: ButtonRole.NORMAL
      })
        .fontSize(14)
        .booleanButton()
        .ButtonLightEffect()
        .overlay(this.LightPoint(),{
          align: Alignment.Center
        })
    }else {
      Button(this.text, {
        type: ButtonType.Normal,
        buttonStyle: this.button?ButtonStyleMode.EMPHASIZED:ButtonStyleMode.NORMAL,
        role: ButtonRole.NORMAL
      })
        .fontSize(14)
        .booleanButton()
    }
  }
}