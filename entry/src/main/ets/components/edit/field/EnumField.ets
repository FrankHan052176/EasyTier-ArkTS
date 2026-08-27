import { AppManager } from '../../../AppManager'
import { ConfigFieldValue } from '../../../config/schema/SchemaConfig'
import { getFieldPathValue, setFieldPathValue, syncFieldPath } from '../../../ConfigSyncUtil'
import { EditRenderOption } from '../../../config/render/EditRenderNode'
import { getFieldI18Name } from '../FieldLabel'
import { LengthMetrics } from '@kit.ArkUI'

@ComponentV2
export struct EnumField {
  @Param @Require field: string
  @Param fieldPath: string[] = [this.field]
  @Param options: EditRenderOption[] = []
  @Consumer("field_edit_enable") enable: boolean = true
  @Local selectedValue: string = ''

  @Computed
  get config() {
    return AppManager.easytier.getEditingConfig()
  }

  private defaultValue(): string {
    if (this.field === 'data_compress_algo') {
      return 'None'
    }
    if (this.field === 'encryption_algorithm') {
      return 'aes-gcm'
    }
    return ''
  }

  private updateFromConfig(): void {
    this.selectedValue = String(getFieldPathValue(this.config!, this.fieldPath) ?? this.defaultValue())
  }

  aboutToAppear(): void {
    this.updateFromConfig()
  }

  aboutToDisappear(): void {
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
    const previous: ConfigFieldValue = getFieldPathValue(this.config!, this.fieldPath)
    const next: string | number = this.optionValue(option.value)
    this.selectedValue = option.value
    setFieldPathValue(this.config!, this.fieldPath, next)
    if (!syncFieldPath(this.config!.instance_id!, this.fieldPath, this.config!)) {
      setFieldPathValue(this.config!, this.fieldPath, previous)
      this.selectedValue = String(previous ?? '')
    }
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
