import { AppManager, Sfp2vp, Svp2fp } from '../../../AppManager';
import { getFieldPathValue, setFieldPathValue, syncFieldPath } from '../../../ConfigSyncUtil';
import { flagsCategory, flagsSymbol } from '../../../util/FlagsInfo';

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

  aboutToAppear(): void {
    this.button = (getFieldPathValue(this.config!, this.fieldPath) as boolean) || false
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
      .width((this.field_width - 10) / 2 - 24)
      .zIndex(2)

      SymbolGlyph(flagsSymbol(this.field))
        .fontSize(Svp2fp((this.field_width - 10) / 8 - 6))
        .fontColor([this.button ? $r("sys.color.font_on_fourth") : $r("sys.color.font_fourth")])
        .zIndex(1)
        .offset({
          x: (this.field_width - 10) * 3 / 8 - 22,
          y: -4
        })
    }
    .padding(12)
    .height(Sfp2vp(12) + Sfp2vp(16) + 12 + 24)
    .width((this.field_width - 10) / 2)
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
