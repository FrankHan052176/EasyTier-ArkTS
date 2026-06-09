import { AppManager } from '../../../AppManager'
import { getFieldPathValue, setFieldPathValue, syncFieldPath } from '../../../ConfigSyncUtil'
import { EditRenderOption } from '../../../config/render/EditRenderNode'
import { getFieldI18Name } from '../FieldLabel'
import { LengthMetrics } from '@kit.ArkUI'
import { getEditingConfigFieldRefreshEvent } from '../../../services/config/storage/StoredConfigService'
import { EventHelper } from '../../../util/EventHelper'

@ComponentV2
export struct EnumField {
  @Param @Require field: string
  @Param fieldPath: string[] = [this.field]
  @Param options: EditRenderOption[] = []
  @Consumer("field_edit_enable") enable: boolean = true
  @Local selectedValue: string = ''
  private fieldRefreshEvent: string = ''
  private fieldRefreshCallback = () => {
    this.updateFromConfig()
  }

  @Computed
  get config() {
    return AppManager.easytier.getEditingConfig()
  }

  private topLevelField(): string {
    return this.fieldPath.length > 0 ? this.fieldPath[0] : this.field
  }

  private updateFromConfig(): void {
    this.selectedValue = String(getFieldPathValue(this.config!, this.fieldPath) ?? '')
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
    this.selectedValue = ''
  }

  private optionValue(raw: string): string | number {
    const num = Number.parseInt(raw)
    if (!Number.isNaN(num) && String(num) === raw) {
      return num
    }
    return raw
  }

  private selectOption(option: EditRenderOption): void {
    if (!this.enable) {
      return
    }
    this.selectedValue = option.value
    setFieldPathValue(this.config!, this.fieldPath, this.optionValue(option.value))
    syncFieldPath(this.config!.instance_id!, this.fieldPath, this.config!)
  }

  @Builder
  optionPill(option: EditRenderOption) {
    Row() {
      Text(option.label)
        .fontSize(13)
        .fontColor(this.selectedValue === option.value ? $r("sys.color.font_on_primary") : $r("sys.color.font_primary"))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .padding({ left: 12, right: 12, top: 8, bottom: 8 })
    .borderRadius(12)
    .backgroundColor(this.selectedValue === option.value ? $r("sys.color.brand") : $r("sys.color.comp_background_primary"))
    .opacity(this.enable ? 1 : 0.5)
    .onClick(() => {
      this.selectOption(option)
    })
  }

  build() {
    Column({ space: 10 }) {
      Text(getFieldI18Name(this.field))
        .fontSize(16)
        .fontColor(this.enable ? $r("sys.color.font_primary") : $r("sys.color.font_tertiary"))
        .width('100%')
      Flex({
        wrap: FlexWrap.Wrap,
        space: {
          main: LengthMetrics.vp(8),
          cross: LengthMetrics.vp(8)
        }
      }) {
        ForEach(this.options, (option: EditRenderOption) => {
          this.optionPill(option)
        }, (option: EditRenderOption) => option.value)
      }
      .width('100%')
    }
    .width('100%')
  }
}
