import { hdsEffect } from '@kit.UIDesignKit';
import { deviceInfo } from '@kit.BasicServicesKit';

export class LightModifier implements AttributeModifier<CommonAttribute> {
  private color: ResourceColor
  private intensity: number
  private height: number

  constructor(color: ResourceColor = Color.White, intensity: number = 1, height: number = 24) {
    this.color = color
    this.intensity = intensity
    this.height = height
  }

  applyNormalAttribute(instance: CommonAttribute): void {
    if (deviceInfo.sdkApiVersion >= 20) {
      instance
        .opacity(0)
        .visualEffect(new hdsEffect.HdsEffectBuilder()
          .pointLight({
            illuminatedType: hdsEffect.PointLightIlluminatedType.BORDER_CONTENT,
            options: {
              color: this.color,
              intensity: this.intensity,
              height: this.height
            }
          }).buildEffect()
        )
    }
  }
}