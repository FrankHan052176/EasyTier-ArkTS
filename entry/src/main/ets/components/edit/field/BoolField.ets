import { AppManager, Sfp2vp, Svp2fp } from '../../../AppManager';
import { getFieldPathValue, setFieldPathValue, syncFieldPath } from '../../../ConfigSyncUtil';
import { flagsCategory, flagsSymbol } from '../../../util/FlagsInfo';
import { getEditingConfigFieldRefreshEvent } from '../../../services/config/storage/StoredConfigService';
import { EventHelper } from '../../../util/EventHelper';

@ComponentV2
export struct BoolField {
  @Param @Require field: string
  @Param fieldPath: string[] = [this.field]
  @Consumer('field_width') field_width: number = 0
  @Param text: ResourceStr = $r("app.string.i18_enable");
  @Local button: boolean = true;
  private fieldRefreshEvent: string = ''
  private fieldRefreshCallback = () => {
    this.updateFromConfig()
  }

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

  private topLevelField(): string {
    return this.fieldPath.length > 0 ? this.fieldPath[0] : this.field
  }

  private updateFromConfig(): void {
    this.button = (getFieldPathValue(this.config!, this.fieldPath) as boolean) || false
  }

  aboutToAppear(): void {
    this.updateFromConfig()
    this.fieldRefreshEvent = getEditingConfigFieldRefreshEvent(this.topLevelField())
    EventHelper.emitterListener(this.fieldRefreshEvent, this.fieldRefreshCallback)
  }

  aboutToDisappear(): void {
    if (this.fieldRefreshEvent.length > 0) {
      EventHelper.emitterOff(this.fieldRefreshEvent, this.fieldRefreshCallback)
      this.fieldRefreshEvent = ''
    }
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
    .height(Sfp2vp(12) + Sfp2vp(16) + 12 + 24)
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
