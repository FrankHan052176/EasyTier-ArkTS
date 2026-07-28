import { AppManager, Sfp2vp, Svp2fp } from '../../../AppManager';
import { getFieldPathValue, setFieldPathValue, syncFieldPath } from '../../../ConfigSyncUtil';
import { flagsCategory, flagsSymbol } from '../../../util/FlagsInfo';

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

  aboutToAppear(): void {
    this.updateFromConfig()
  }

  /**
   * 复用时 @Local 会被重置为初始值（button 会变回 true），
   * 这里必须按复用后新的 fieldPath 重新读取真实值，否则开关状态会串行。
   */
  aboutToReuse(): void {
    this.updateFromConfig()
  }

  aboutToDisappear(): void {
    this.button = false
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
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
      })
      syncFieldPath(this.config!.instance_id!, this.fieldPath, this.config!)
    })
  }
}
