import { AppManager, Sfp2vp, Svp2fp } from '../../../AppManager';
import { getFieldPathValue, setFieldPathValue, syncFieldPath } from '../../../ConfigSyncUtil';
import { flagsCategory, flagsSymbol } from '../../../util/FlagsInfo';
import { NodeContent, Theme } from '@kit.ArkUI';
import nativeUi from 'libeasytier_ui.so';

interface NativeBoolTextModel {
  category: string
  text: string
  width: number
  height: number
  categoryColor: number
  textColor: number
}

const NATIVE_BOOL_TEXT_ENABLED: boolean = true

/**
 * BoolField 的固定行高（与 build() 里的 .height() 保持一致）。
 * 导出给 List 的 ListItem 定高用：给了确定高度，List 就不必
 * 往下钻进子树做内容测量。
 */
export function boolFieldHeight(): number {
  return Sfp2vp(12) + Sfp2vp(16) + 12 + 24
}

/**
 * 标记为可复用：flags 页一屏 22 个实例，LazyForEach 在滑出缓存范围时会销毁、
 * 滑回来再重建。实测这些重建占了 flags 行测量成本的 78%
 * （CustomNode:BuildItem 33.9ms / 行测量合计 43.5ms）。
 * 复用后组件实例进回收池，回来时只走 aboutToReuse 重新绑数据。
 */
@ReusableV2
@ComponentV2
export struct BoolField {
  @Param @Require field: string
  @Param fieldPath: string[] = [this.field]
  @Consumer('field_width') field_width: number = 0
  @Param text: ResourceStr = $r("app.string.i18_enable");
  @Local button: boolean = true;
  @Local nativeReady: boolean = NATIVE_BOOL_TEXT_ENABLED
  private nativeContent: NodeContent = new NodeContent()
  private nativeCreated: boolean = false
  private active: boolean = false
  private themeFontPrimary: ResourceColor | undefined = undefined
  private themeFontSecondary: ResourceColor | undefined = undefined
  private themeFontOnPrimary: ResourceColor | undefined = undefined
  private themeFontOnSecondary: ResourceColor | undefined = undefined

  @Computed
  get config() {
    return AppManager.easytier.getEditingConfig()
  }

  @Computed
  get safeFieldWidth() {
    return this.field_width > 10 ? this.field_width : 360
  }

  @Computed
  get cellWidth() {
    return Math.max(140, (this.safeFieldWidth - 10) / 2)
  }

  @Computed
  get textWidth() {
    return Math.max(92, this.cellWidth - 24)
  }

  @Computed
  get symbolSize() {
    return Math.max(18, Svp2fp((this.safeFieldWidth - 10) / 8 - 6))
  }

  private updateFromConfig(): void {
    this.button = (getFieldPathValue(this.config!, this.fieldPath) as boolean) || false
  }

  private resolvedText(): string | undefined {
    if (typeof this.text === 'string') {
      return this.text
    }
    try {
      return AppManager.content.context!.resourceManager.getStringSync((this.text as Resource).id)
    } catch (_) {
      return undefined
    }
  }

  private resolvedColor(color: ResourceColor): number | undefined {
    if (typeof color === 'number') {
      return color >>> 0
    }
    if (typeof color === 'string') {
      if (color.startsWith('#') && (color.length === 7 || color.length === 9)) {
        const parsed = Number.parseInt(color.substring(1), 16)
        if (!Number.isNaN(parsed)) {
          return color.length === 7 ? (0xFF000000 | parsed) >>> 0 : parsed >>> 0
        }
      }
      return undefined
    }
    try {
      return AppManager.content.context!.resourceManager.getColorSync((color as Resource).id) >>> 0
    } catch (_) {
      return undefined
    }
  }

  private nativeModel(): NativeBoolTextModel | undefined {
    const text = this.resolvedText()
    const categoryColor = this.resolvedColor(this.button ?
      (this.themeFontOnSecondary ?? $r("sys.color.font_on_secondary")) :
      (this.themeFontSecondary ?? $r("sys.color.font_secondary")))
    const textColor = this.resolvedColor(this.button ?
      (this.themeFontOnPrimary ?? $r("sys.color.font_on_primary")) :
      (this.themeFontPrimary ?? $r("sys.color.font_primary")))
    if (text === undefined || categoryColor === undefined || textColor === undefined) {
      return undefined
    }
    return {
      category: flagsCategory(this.field),
      text: text,
      width: this.textWidth,
      height: Math.max(0, boolFieldHeight() - 24),
      categoryColor: categoryColor,
      textColor: textColor
    }
  }

  private destroyNativeText(): void {
    if (!this.nativeCreated) {
      return
    }
    try {
      nativeUi.destroyBoolText(this.nativeContent)
    } catch (_) {
    }
    this.nativeCreated = false
  }

  private disableNativeText(): void {
    this.destroyNativeText()
    this.nativeReady = false
  }

  private createNativeText(): void {
    if (!this.active || !this.nativeReady) {
      return
    }
    const model = this.nativeModel()
    if (!model) {
      this.disableNativeText()
      return
    }
    try {
      this.nativeCreated = nativeUi.createBoolText(this.nativeContent, model)
      if (!this.nativeCreated) {
        this.disableNativeText()
      }
    } catch (_) {
      this.disableNativeText()
    }
  }

  private updateNativeText(): void {
    if (!this.active || !this.nativeReady) {
      return
    }
    if (!this.nativeCreated) {
      this.createNativeText()
      return
    }
    const model = this.nativeModel()
    if (!model) {
      this.disableNativeText()
      return
    }
    try {
      if (!nativeUi.updateBoolText(this.nativeContent, model)) {
        this.disableNativeText()
      }
    } catch (_) {
      this.disableNativeText()
    }
  }

  aboutToAppear(): void {
    this.active = true
    this.updateFromConfig()
    this.createNativeText()
  }

  onWillApplyTheme(theme: Theme): void {
    this.themeFontPrimary = theme.colors.fontPrimary
    this.themeFontSecondary = theme.colors.fontSecondary
    this.themeFontOnPrimary = theme.colors.fontOnPrimary
    this.themeFontOnSecondary = theme.colors.fontOnSecondary
    this.updateNativeText()
  }

  @Monitor('field_width')
  onFieldWidthChange(): void {
    this.updateNativeText()
  }

  /**
   * 复用时 @Local 会被重置为初始值（button 会变回 true），
   * 这里必须按复用后新的 fieldPath 重新读取真实值，否则开关状态会串行。
   */
  aboutToReuse(): void {
    this.active = true
    this.nativeReady = NATIVE_BOOL_TEXT_ENABLED
    this.updateFromConfig()
    this.updateNativeText()
  }

  aboutToRecycle(): void {
    this.active = false
  }

  aboutToDisappear(): void {
    this.active = false
    this.destroyNativeText()
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      if (this.nativeReady) {
        ContentSlot(this.nativeContent)
      } else {
        Column({ space: 12 }) {
          Text(flagsCategory(this.field))
            .fontSize(12)
            .textAlign(TextAlign.Start)
            .maxLines(1)
            .textOverflow({
              overflow: TextOverflow.Ellipsis
            })
            .fontColor(this.button ? $r("sys.color.font_on_secondary") : $r("sys.color.font_secondary"))
          Text(this.text)
            .textAlign(TextAlign.Start)
            .maxLines(1)
            .textOverflow({
              overflow: TextOverflow.Ellipsis
            })
            .fontColor(this.button ? $r("sys.color.font_on_primary") : $r("sys.color.font_primary"))
        }
        .height('100%')
        .alignItems(HorizontalAlign.Start)
        .justifyContent(FlexAlign.SpaceBetween)
        .width(this.textWidth)
        .zIndex(2)
      }

      SymbolGlyph(flagsSymbol(this.field))
        .fontSize(this.symbolSize)
        .fontColor([this.button ? $r("sys.color.font_on_fourth") : $r("sys.color.font_fourth")])
        .zIndex(1)
        .offset({
          x: this.cellWidth * 3 / 4 - 22,
          y: -4
        })
    }
    .padding(12)
    .height(boolFieldHeight())
    .width(this.cellWidth)
    .backgroundColor(this.button ? $r("sys.color.brand") : $r("sys.color.comp_background_primary"))
    .borderRadius(18)
    .clickEffect({
      level: ClickEffectLevel.LIGHT
    })
    .onClick(() => {
      animateToImmediately({
        curve: Curve.FastOutSlowIn,
        duration: 300
      }, () => {
        this.button = !this.button
        setFieldPathValue(this.config!, this.fieldPath, this.button)
        this.updateNativeText()
      })
      syncFieldPath(this.config!.instance_id!, this.fieldPath, this.config!)
    })
  }
}
