import { deviceInfo } from '@kit.BasicServicesKit';
import { hdsEffect } from '@kit.UIDesignKit';

export class StackLightModifier implements AttributeModifier<StackAttribute> {
  applyNormalAttribute(instance: StackAttribute): void {
    if (deviceInfo.sdkApiVersion >= 20) {
      instance
        .visualEffect(new hdsEffect.HdsEffectBuilder()
          .pointLight({
            illuminatedType: hdsEffect.PointLightIlluminatedType.CONTENT
          })
          .buildEffect()
        )
    }
  }
}