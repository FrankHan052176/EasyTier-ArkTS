import { LengthMetrics } from '@kit.ArkUI'
import { BusinessError } from '@kit.BasicServicesKit'
import { userAuth } from '@kit.UserAuthenticationKit'
import { AppManager } from '../../AppManager'
import { addFieldValue } from '../../class/config/Basic'
import { hasFieldTag, isVaultField } from '../../config/fields/ConfigFieldUi'
import { EditRenderNode } from '../../config/render/EditRenderNode'
import { collectTopLevelFields } from '../../config/render/EditRenderResolver'
import { areEditingFieldsLoaded, getEditingConfigFieldRefreshEvent } from '../../services/config/storage/StoredConfigService'
import { EventHelper } from '../../util/EventHelper'
import { BoolField } from './field/BoolField'
import { CidrField } from './field/CidrField'
import { EnableField } from './field/EnableField'
import { EnumField } from './field/EnumField'
import { ListField } from './field/ListField'
import { NumberField } from './field/NumberField'
import { PortField } from './field/PortField'
import { StringField } from './field/StringField'
import { UnsupportedField } from './field/UnsupportedField'
import { getFieldI18Name } from './FieldEdit'
import { PrimaryButton } from '../util/TextButton'

@ComponentV2
export struct RecursiveJsonEditor {
  @Param @Require node: EditRenderNode
  @Param layer: number = 0
  @Provider() field_width: number = 0
  @Local content_height: number = 0
  @Provider("field_edit_enable") enable: boolean = true
  @Local maskOpacity: number = 1
  @Local blurRadius: number = 40
  @Local nodeReady: boolean = true
  @Consumer("unsafe_status") unsafe: boolean = false
  @Consumer("peep_masked") peepMasked: boolean = false
  @Consumer("peep_dismissed") peepDismissed: boolean = false
  @Provider("lock_status") unlock: boolean = !isVaultField(this.node.name)
  private fieldRefreshEvents: string[] = []
  private fieldRefreshCallback = () => {
    this.updateNodeReady()
  }

  @Computed
  get safe_show() {
    if (!isVaultField(this.node.name)) {
      return true
    }
    if (this.peepMasked) {
      return false
    }
    if (AppManager.uiState.vault_mode) {
      return this.unlock
    }
    return true
  }

  @Computed
  get hasEnableButton() {
    return this.node.enableNode !== undefined
  }

  @Computed
  get isHidden() {
    return hasFieldTag(this.node.name, "hidable") && !this.enable
  }

  @Computed
  get isHideTitle() {
    return hasFieldTag(this.node.name, "hideTitle")
  }

  @Computed
  get isUseDivider() {
    return hasFieldTag(this.node.name, "useDivider")
  }

  @Computed
  get titleFontSize() {
    return this.layer === 0 ? 14 : 16
  }

  @Computed
  get isSingleField() {
    return this.layer >= 1 || this.node.kind === 'list' || this.node.name === "flags_switch"
  }

  @Computed
  get Padding() {
    return this.isSingleField ? 0 : 16
  }

  private contentNodes(): EditRenderNode[] {
    if (this.hasEnableButton) {
      return this.node.children.slice(1)
    }
    return this.node.children
  }

  private isListNode(node: EditRenderNode): boolean {
    return node.kind === 'list' && node.listType !== undefined
  }

  private topLevelFields(): string[] {
    return collectTopLevelFields(this.node)
  }

  private updateNodeReady(): void {
    this.nodeReady = areEditingFieldsLoaded(AppManager.uiState.editingInstance, this.topLevelFields())
  }

  private unbindFieldRefreshEvents(): void {
    this.fieldRefreshEvents.forEach((eventName) => {
      EventHelper.emitterOff(eventName, this.fieldRefreshCallback)
    })
    this.fieldRefreshEvents = []
  }

  private bindFieldRefreshEvents(): void {
    this.unbindFieldRefreshEvents()
    this.topLevelFields().forEach((field) => {
      const eventName = getEditingConfigFieldRefreshEvent(field)
      this.fieldRefreshEvents.push(eventName)
      EventHelper.emitterListener(eventName, this.fieldRefreshCallback)
    })
  }

  aboutToAppear(): void {
    this.updateNodeReady()
    this.bindFieldRefreshEvents()
  }

  aboutToDisappear(): void {
    this.unbindFieldRefreshEvents()
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
        Text(getFieldI18Name(this.node.name))
          .fontSize(this.titleFontSize)
          .focusable(false)
        if (this.nodeReady && this.hasEnableButton && this.node.enableNode) {
          EnableField({
            field: this.node.enableNode.name,
            fieldPath: this.node.enableNode.path
          })
        } else if (this.nodeReady && this.isListNode(this.node)) {
          PrimaryButton({ text: "新增", fontSize: this.titleFontSize, fontColor: $r("sys.color.brand_font") })
            .clickEffect({
              level: ClickEffectLevel.MIDDLE
            })
            .onClick(() => {
              addFieldValue(this.node.listType!, this.node.name)
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
  skeletonLine(widthValue: string, heightValue: number, radiusValue: number) {
    Row()
      .width(widthValue)
      .height(heightValue)
      .borderRadius(radiusValue)
      .backgroundColor($r('sys.color.comp_background_secondary'))
      .opacity(0.56)
  }

  @Builder
  loadingSkeleton() {
    Column({ space: 8 }) {
      this.skeletonLine('42%', 10, 5)
      this.skeletonLine('100%', 36, 12)
    }
    .width('100%')
    .height(56)
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  fieldContent(node: EditRenderNode) {
    if (node.kind === 'boolean') {
      BoolField({ field: node.name, fieldPath: node.path, text: getFieldI18Name(node.name) })
    } else if (node.kind === 'string') {
      StringField({ field: node.name, fieldPath: node.path })
    } else if (node.kind === 'port') {
      PortField({ field: node.name, fieldPath: node.path, text: getFieldI18Name(node.name) })
    } else if (node.kind === 'number') {
      NumberField({ field: node.name, fieldPath: node.path })
    } else if (node.kind === 'cidr') {
      CidrField({ field: node.name, fieldPath: node.path, text: getFieldI18Name(node.name) })
    } else if (node.kind === 'enum') {
      EnumField({ field: node.name, fieldPath: node.path, options: node.enumOptions })
    } else if (node.kind === 'list' && node.listType) {
      ListField({ field: node.name, type: node.listType })
    } else if (node.kind === 'group') {
      RecursiveJsonEditor({ node: node, layer: this.layer + 1 })
    } else {
      UnsupportedField({ field: node.name, fieldPath: node.path })
    }
  }

  @Builder
  content() {
    if (!this.nodeReady) {
      this.loadingSkeleton()
    } else if (!this.isHidden) {
      if (this.node.kind === 'group') {
        Flex({
          wrap: FlexWrap.Wrap,
          space: {
            main: LengthMetrics.vp(10),
            cross: LengthMetrics.vp(10)
          }
        }) {
          ForEach(this.contentNodes(), (child: EditRenderNode, index: number) => {
            if (child.kind === 'boolean') {
              this.fieldContent(child)
            } else {
              Column() {
                this.fieldContent(child)
              }
              .width('100%')
              .padding({
                left: this.Padding,
                right: this.Padding,
                top: (this.isUseDivider && index > 0) ? 6 : 0,
                bottom: (this.isUseDivider && index < this.contentNodes().length - 1) ? 6 : 0
              })
            }
            if (this.isUseDivider && index < this.contentNodes().length - 1) {
              Divider()
                .color($r("sys.color.background_secondary"))
                .width('100%')
                .strokeWidth(3)
            }
          }, (item: EditRenderNode) => item.path.join('.') + item.kind)
        }
        .width('100%')
        .onAreaChange((a, b) => {
          this.field_width = b.width.valueOf() as number
        })
      } else {
        this.fieldContent(this.node)
      }
    }
  }

  private requestUnlock() {
    const authParam: userAuth.AuthParam = {
      challenge: new Uint8Array([49, 50, 51, 52, 53, 54]),
      authType: [userAuth.UserAuthType.FACE, userAuth.UserAuthType.FINGERPRINT, userAuth.UserAuthType.PIN],
      authTrustLevel: userAuth.AuthTrustLevel.ATL1,
    }
    const widgetParam: userAuth.WidgetParam = {
      title: '请输入密码或生物识别以解锁',
    }
    try {
      const userAuthInstance = userAuth.getUserAuthInstance(authParam, widgetParam)
      userAuthInstance.on('result', {
        onResult: (result) => {
          if (result.result === userAuth.UserAuthResultCode.SUCCESS) {
            animateToImmediately({
              duration: 500, curve: Curve.EaseOut, onFinish: () => {
                this.unlock = true
                if (this.peepMasked) {
                  this.peepMasked = false
                  this.peepDismissed = true
                }
              }
            }, () => {
              this.maskOpacity = 0
              this.blurRadius = 0
            })
          }
        }
      })
      userAuthInstance.start()
    } catch (error) {
      console.error(`auth catch error: ${(error as BusinessError).code} ${(error as BusinessError).message}`)
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
    .borderRadius({ topLeft: 0, topRight: 0, bottomLeft: 18, bottomRight: 18 })
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
