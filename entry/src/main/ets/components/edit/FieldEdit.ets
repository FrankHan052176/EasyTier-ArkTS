import { ConfigField, ContentUtil } from '../../ContentUtil'
import { NetworkConfig } from '../../protobuf/api_manage'
import { BoolField } from './field/BoolField'
import { LengthMetrics } from '@kit.ArkUI'
import { deviceInfo } from '@kit.BasicServicesKit'
import { hdsEffect } from '@kit.UIDesignKit'
import { StringField } from './field/StringField'
import { PortField } from './field/PortField'
import { WaterFlowField } from './field/WaterFlowField'
import { Svp2fp } from '../../AppManager'
import { EnableField } from './field/EnableField'
import { ToolButton } from '../util/ToolButtons'
import { CidrField } from './field/CidrField'

@Extend(Column)
function ColumnLightEffect() {
  .visualEffect(new hdsEffect.HdsEffectBuilder().pointLight({
    illuminatedType: hdsEffect.PointLightIlluminatedType.BORDER,
  }).buildEffect())
}

export function getFieldI18Name(field: string): Resource {
  return $r("app.string."+field)
}

@ComponentV2
export struct FieldEdit {
  @Param @Require config: NetworkConfig
  @Param @Require field: ConfigField
  @Provider() field_width: number = 0
  @Local hasEnableButton: boolean = Array.isArray(this.field.type) && this.field.type[0].type === "boolean" && this.field.name !== "flags_switch"
  @Local enable: boolean = true
  @Local enableField: string = this.hasEnableButton?(this.field.type[0] as ConfigField).name:""

  getFieldName(): string {
    return this.field.name
  }

  getFields(): ConfigField[] {
    if (Array.isArray(this.field.type)) {
      if (this.hasEnableButton) {
        return this.field.type.slice(1)
      }else {
        return this.field.type
      }
    }else {
      return [this.field]
    }
  }

  @Computed
  get isEnabled() {
    if (ContentUtil.hasTag(this.enableField,"inverse")) {
      return !this.enable
    }else {
      return this.enable
    }
  }

  @Computed
  get isHidden() {
    if (ContentUtil.hasTag(this.field.name, "hidable") && !this.enable) {
      return true
    }else {
      return false
    }
  }

  @Computed
  get isHideTitle() {
    return ContentUtil.hasTag(this.field.name, "hideTitle")
  }

  isLisType(field: ConfigField): boolean {
    return typeof field.type === "string" && field.type.endsWith("[]")
  }

  @Builder
  content() {
    if (!this.isHideTitle) {
      Row() {
        Text(getFieldI18Name(this.getFieldName()))
          .fontSize(Svp2fp(18))
          .focusable(false)
        if (this.hasEnableButton) {
          EnableField({config: this.config, field: this.enableField, bind: this.enable!!})
        }else if (this.isLisType(this.field)) {
          ToolButton({symbol: $r("sys.symbol.plus"), buttonSize: 26, symbolScale: 0.8})
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .justifyContent(FlexAlign.SpaceBetween)
      .focusable(false)
      .margin({top: this.isHidden&&!this.isEnabled?0:5})
    }
    if (!this.isHidden) {
      Flex({wrap: FlexWrap.Wrap, space: {
        main: LengthMetrics.vp(10),
        cross: LengthMetrics.vp(10)
      }}) {
        ForEach(this.getFields(), (field: ConfigField, index: number) => {
          if (field.type === "boolean") {
            BoolField({config: this.config, field: field.name, text: getFieldI18Name(field.name)})
              .enabled(this.isEnabled)
          }else if (field.type === "string") {
            StringField({config: this.config, field: field.name})
              .enabled(this.isEnabled)
          }else if (field.type === "port") {
            PortField({config: this.config, field: field.name, text: getFieldI18Name(field.name)})
              .enabled(this.isEnabled)
          }else if (this.isLisType(field)) {
            WaterFlowField({config: this.config, field: field.name, type: (field.type as string).slice(0, field.type.length-2)})
          }else if (field.type === "cidr") {
            CidrField({config: this.config, field: field.name, text: getFieldI18Name(field.name)})
              .enabled(this.isEnabled)
          }else {
            Text(field.name+":"+(field.type as string))
              .width('100%')
              .enabled(this.isEnabled)
          }
        }, (item: ConfigField) => {return item.name+item.type})
      }
      .width('100%')
      .margin({top: 5})
      .onAreaChange((a,b) => {
        this.field_width = b.width.valueOf() as number
      })
    }
  }

  @Styles
  backgroundColumn() {
    .width('100%')
    .borderRadius(18)
    .backgroundColor($r("sys.color.comp_background_primary"))
    .padding(10)
    .clip(true)
  }

  build() {
    if (deviceInfo.sdkApiVersion >= 20) {
      Column() {
        this.content()
      }
      .backgroundColumn()
      .ColumnLightEffect()
    }else {
      Column() {
        this.content()
      }
      .backgroundColumn()
    }
  }
}