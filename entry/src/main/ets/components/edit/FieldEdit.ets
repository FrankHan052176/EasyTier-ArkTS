import { ConfigField, ContentUtil } from '../../ContentUtil'
import { BoolField } from './field/BoolField'
import { LengthMetrics } from '@kit.ArkUI'
import { StringField } from './field/StringField'
import { PortField } from './field/PortField'
import { ListField as ListField } from './field/ListField'
import { EnableField } from './field/EnableField'
import { CidrField } from './field/CidrField'
import { PrimaryButton } from '../util/TextButton'
import { addFieldValue } from '../../class/config/Basic'
import { Logger } from '../../util/Logger'
import { AppManager } from '../../AppManager'

export function getFieldI18Name(field: string): Resource {
  return $r("app.string."+(ContentUtil.renamedField[field] || field))
}

@ComponentV2
export struct FieldEdit {
  @Param layer: number = 0
  @Param @Require field: ConfigField
  @Provider() field_width: number = 0
  @Local hasEnableButton: boolean = Array.isArray(this.field.type) && this.field.type[0].type === "boolean" && this.field.name !== "flags_switch"
  @Local enableField: string = this.hasEnableButton?(this.field.type[0] as ConfigField).name:""
  @Provider("field_edit_enable") enable: boolean = true

  @Computed
  get config() {
    return AppManager.data.configUUIDMap.get(AppManager.data.editingInstance ?? "")
  }

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

  @Computed
  get isCidr() {
    return Array.isArray(this.field.type) && this.field.type.length === 2 && this.field.type[0].type === "cidr_ip" && this.field.type[1].type === "cidr_mask"
  }

  @Computed
  get isUseDivider() {
    return ContentUtil.hasTag(this.field.name, "useDivider")
  }

  @Styles
  backgroundColumn() {
    .width('100%')
    .borderRadius(this.isSingleField?0:18)
    .backgroundColor(this.isSingleField?Color.Transparent:$r("sys.color.comp_background_primary"))
    .clip(true)
    .padding({top: this.Padding, bottom: this.Padding})
  }

  @Computed
  get titleFontSize() {
    return this.layer===0?14:16
  }

  @Computed
  get isSingleField() {
    return this.layer >= 1 || this.isLisType(this.field) || this.field.name === "flags_switch"
  }

  @Computed
  get Padding() {
    return this.isSingleField?0:16
  }

  @Builder
  title() {
    if (!this.isHideTitle) {
      Row() {
        Text(getFieldI18Name(this.getFieldName()))
          .fontSize(this.titleFontSize)
          .focusable(false)
        if (this.hasEnableButton) {
          EnableField({field: this.enableField})
        }else if (this.isLisType(this.field)) {
          PrimaryButton({text: "新增", fontSize: this.titleFontSize, fontColor: $r("sys.color.brand_font")})
            .clickEffect({
              level: ClickEffectLevel.MIDDLE
            })
            .onClick(() => {
              addFieldValue((this.field.type as string).slice(0, this.field.type.length-2), this.field.name)
            })
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .justifyContent(FlexAlign.SpaceBetween)
      .focusable(false)
    }
  }

  @Builder
  content() {
    if (!this.isHidden) {
      Flex({wrap: FlexWrap.Wrap, space: {
        main: LengthMetrics.vp(10),
        cross: LengthMetrics.vp(10)
      }}) {
        ForEach(this.getFields(), (field: ConfigField, index) => {
          if (field.type === "boolean") {
            BoolField({field: field.name, text: getFieldI18Name(field.name)})
          }else {
            Column() {
              if (field.type === "string") {
                StringField({field: field.name})
              }else if (field.type === "port") {
                PortField({field: field.name, text: getFieldI18Name(field.name)})
              }else if (this.isLisType(field)) {
                ListField({field: field.name, type: (field.type as string).slice(0, field.type.length-2)})
              }else if (Array.isArray(field.type) && field.type.length === 2 && field.type[0].type === "cidr_ip" && field.type[1].type === "cidr_mask") {
                CidrField({field: field.name, text: getFieldI18Name(field.name)})
              }else if (Array.isArray(field.type)) {
                FieldEdit({field: field, layer: this.layer + 1})
              }else {
                Text(field.name+":"+(field.type as string))
                  .width('100%')
              }
            }
            .width('100%')
            .padding({left: this.Padding, right: this.Padding})
          }
          if (this.isUseDivider) {
            if (index < this.getFields().length - 1) {
              Divider()
                .color($r("sys.color.background_secondary"))
                .width('100%')
                .strokeWidth(1)
                .margin({top: 6, bottom: 6})
            }
          }
        }, (item: ConfigField) => {return item.name+item.type})
      }
      .width('100%')
      .onAreaChange((a,b) => {
        this.field_width = b.width.valueOf() as number
      })
    }
  }

  build() {
    Column() {
      if (this.layer === 0) {
        Row() {
          this.title()
        }
        .padding({left: 5, bottom: 10, right: 5})
      }
      Column({space: 8}) {
        if (this.layer > 0) {
          this.title()
        }
        this.content()
      }
      .backgroundColumn()
    }
  }
}