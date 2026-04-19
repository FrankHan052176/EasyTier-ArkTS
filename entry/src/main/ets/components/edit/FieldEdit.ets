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
import { AppManager } from '../../AppManager'
import { NumberField } from './field/NumberField'
import { SecureModeConfigField } from './field/SecureModeConfig'
import { userAuth } from '@kit.UserAuthenticationKit'
import { BusinessError } from '@kit.BasicServicesKit'
import { hdsEffect } from '@kit.UIDesignKit'

export function getFieldI18Name(field: string): ResourceStr {
  return $r("app.string." + (ContentUtil.renamedField[field] || field))
}

@ComponentV2
export struct FieldEdit {
  @Param layer: number = 0
  @Param @Require field: ConfigField
  @Provider() field_width: number = 0
  @Local content_height: number = 0
  @Local hasEnableButton: boolean =
    Array.isArray(this.field.type) && this.field.type[0].type === "boolean" && this.field.name !== "flags_switch"
  @Local enableField: string = this.hasEnableButton ? (this.field.type[0] as ConfigField).name : ""
  @Provider("field_edit_enable") enable: boolean = true
  @Local maskOpacity: number = 1;
  @Local blurRadius: number = 40;
  @Consumer("unsafe_status") unsafe: boolean = false
  @Provider("lock_status") unlock: boolean = !ContentUtil.isVaultField(this.getFieldName())

  @Computed
  get safe_show() {
    return !this.unsafe || this.unlock || !AppManager.preference.vault_mode
  }

  @Computed
  get config() {
    return AppManager.easytier.getEditingConfig()
  }

  @Computed
  get preference() {
    return AppManager.preference.configPreferences.get(AppManager.uiState.editingInstance ?? "")
  }

  @Computed
  get isHidden() {
    if (ContentUtil.hasTag(this.field.name, "hidable") && !this.enable) {
      return true
    } else {
      return false
    }
  }

  @Computed
  get isHideTitle() {
    return ContentUtil.hasTag(this.field.name, "hideTitle")
  }

  @Computed
  get isCidr() {
    return Array.isArray(this.field.type) && this.field.type.length === 2 && this.field.type[0].type === "cidr_ip" &&
      this.field.type[1].type === "cidr_mask"
  }

  @Computed
  get isUseDivider() {
    return ContentUtil.hasTag(this.field.name, "useDivider")
  }

  @Computed
  get titleFontSize() {
    return this.layer === 0 ? 14 : 16
  }

  @Computed
  get isSingleField() {
    return this.layer >= 1 || this.isLisType(this.field) || this.field.name === "flags_switch"
  }

  @Computed
  get Padding() {
    return this.isSingleField ? 0 : 16
  }

  getFieldName(): string {
    return this.field.name
  }

  getFields(): ConfigField[] {
    if (Array.isArray(this.field.type)) {
      if (this.hasEnableButton) {
        return this.field.type.slice(1)
      } else {
        return this.field.type
      }
    } else {
      return [this.field]
    }
  }

  isLisType(field: ConfigField): boolean {
    return typeof field.type === "string" && field.type.endsWith("[]")
  }

  @Styles
  backgroundColumn() {
    .width('100%')
    .borderRadius(this.isSingleField ? 0 : 18)
    .backgroundColor(this.isSingleField ? Color.Transparent : $r("sys.color.comp_background_primary"))
    .clip(true)
    .padding({ top: this.Padding, bottom: this.Padding })
  }

  @Builder
  title() {
    if (!this.isHideTitle) {
      Row() {
        Text(getFieldI18Name(this.getFieldName()))
          .fontSize(this.titleFontSize)
          .focusable(false)
        if (this.hasEnableButton) {
          EnableField({ field: this.enableField })
        } else if (this.isLisType(this.field)) {
          PrimaryButton({ text: "新增", fontSize: this.titleFontSize, fontColor: $r("sys.color.brand_font") })
            .clickEffect({
              level: ClickEffectLevel.MIDDLE
            })
            .onClick(() => {
              addFieldValue((this.field.type as string).slice(0, this.field.type.length - 2), this.field.name)
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
      Flex({
        wrap: FlexWrap.Wrap, space: {
          main: LengthMetrics.vp(10),
          cross: LengthMetrics.vp(10)
        }
      }) {
        ForEach(this.getFields(), (field: ConfigField, index) => {
          if (field.type === "boolean") {
            BoolField({ field: field.name, text: getFieldI18Name(field.name) })
          } else {
            Column() {
              if (field.type === "string") {
                StringField({ field: field.name })
              } else if (field.type === "port") {
                PortField({ field: field.name, text: getFieldI18Name(field.name) })
              } else if (this.isLisType(field)) {
                ListField({ field: field.name, type: (field.type as string).slice(0, field.type.length - 2) })
              } else if (Array.isArray(field.type) && field.type.length === 2 && field.type[0].type === "cidr_ip" &&
                field.type[1].type === "cidr_mask") {
                CidrField({ field: field.name, text: getFieldI18Name(field.name) })
              } else if (Array.isArray(field.type)) {
                FieldEdit({ field: field, layer: this.layer + 1 })
              } else if (field.type === "number") {
                NumberField({ field: field.name })
              } else if (field.type === "common.SecureModeConfig") {
                SecureModeConfigField({ field: field.name })
              } else {
                Text(field.name + " 功能暂未适配")
                  .width('100%')
              }
            }
            .width('100%')
            .padding({
              left: this.Padding,
              right: this.Padding,
              top: (this.isUseDivider && index > 0) ? 6 : 0,
              bottom: (this.isUseDivider && index < this.getFields().length - 1) ? 6 : 0
            })
          }
          if (this.isUseDivider) {
            if (index < this.getFields().length - 1) {
              Divider()
                .color($r("sys.color.background_secondary"))
                .width('100%')
                .strokeWidth(3)
            }
          }
        }, (item: ConfigField) => {
          return item.name + item.type
        })
      }
      .width('100%')
      .onAreaChange((a, b) => {
        this.field_width = b.width.valueOf() as number
      })
    }
  }

  private requestUnlock() {
    const authParam: userAuth.AuthParam = {
      challenge: new Uint8Array([49, 50, 51, 52, 53, 54]),
      authType: [userAuth.UserAuthType.FACE, userAuth.UserAuthType.FINGERPRINT, userAuth.UserAuthType.PIN],
      authTrustLevel: userAuth.AuthTrustLevel.ATL1,
    };
    const widgetParam: userAuth.WidgetParam = {
      title: '请输入密码或生物识别以解锁',
    };
    try {
      const userAuthInstance = userAuth.getUserAuthInstance(authParam, widgetParam);
      userAuthInstance.on('result', {
        onResult: (result) => {
          if (result.result === userAuth.UserAuthResultCode.SUCCESS) {
            animateTo({
              duration: 500, curve: Curve.EaseOut, onFinish: () => {
                this.unlock = true;
              }
            }, () => {
              this.maskOpacity = 0;
              this.blurRadius = 0;
            })
          }
        }
      });
      userAuthInstance.start();
    } catch (error) {
      console.error(`auth catch error: ${(error as BusinessError).code} ${(error as BusinessError).message}`);
    }
  }

  build() {
    Column() {
      if (this.layer === 0) {
        Row() {
          this.title()
        }
        .padding({ left: 5, bottom: 10, right: 5 })
      }

      // 使用 Stack 仅包裹背景卡片区域
      Stack() {
        Column({ space: 8 }) {
          if (this.layer > 0) {
            this.title()
          }
          this.content()
        }
        .backgroundColumn()
        .blur(this.safe_show ? 0 : this.blurRadius)
        .onAreaChange((a, b) => {
          this.content_height = b.height.valueOf() as number
        })

        // 只有在未解锁或动画进行中时显示遮罩
        if (!this.safe_show) {
          Stack({ alignContent: Alignment.Center }) {
            this.maskBuilder()
          }
          .width('100%')
          .height(1)
          .clip(false)
        }
      }
      .width('100%')
      .clip(false)
    }
  }

  @Builder
  maskBuilder() {
    Column() {
      SymbolGlyph($r('sys.symbol.lock_fill'))
        .fontSize(28)
        .fontColor([$r('sys.color.font_tertiary')])
    }
    .width(this.field_width + 32)
    .height(this.content_height + 32)
    .borderRadius({topLeft: 0, topRight: 0, bottomLeft: 18, bottomRight: 18})
    .backgroundColor($r("app.color.vault_cover"))
    .backgroundBlurStyle(BlurStyle.Thick,
      { colorMode: ThemeColorMode.SYSTEM, adaptiveColor: AdaptiveColor.DEFAULT, scale: 1.0 })
    .justifyContent(FlexAlign.Center)
    .opacity(this.maskOpacity)
    .onClick(() => {
      this.requestUnlock()
    })
    .hitTestBehavior(HitTestMode.Block)
  }
}
