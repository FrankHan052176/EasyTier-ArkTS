import { deviceInfo } from "@kit.BasicServicesKit";
import { hdsEffect } from "@kit.UIDesignKit";

export class ColumnIlluminatedModifier implements AttributeModifier<ColumnAttribute> {
  applyNormalAttribute(instance: ColumnAttribute): void {
    if (deviceInfo.sdkApiVersion >= 20) {
      instance
        .visualEffect(new hdsEffect.HdsEffectBuilder()
          .pointLight({
            illuminatedType: hdsEffect.PointLightIlluminatedType.BORDER
          }).buildEffect())
    }
  }
}

export class RowIlluminatedModifier implements AttributeModifier<RowAttribute> {
  applyNormalAttribute(instance: RowAttribute): void {
    if (deviceInfo.sdkApiVersion >= 20) {
      instance
        .visualEffect(new hdsEffect.HdsEffectBuilder()
          .pointLight({
            illuminatedType: hdsEffect.PointLightIlluminatedType.BORDER
          }).buildEffect())
    }
  }
}