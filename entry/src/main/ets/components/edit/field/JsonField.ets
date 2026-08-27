import { AppManager } from '../../../AppManager'
import { ConfigFieldValue, ConfigJson } from '../../../config/schema/SchemaConfig'
import { getFieldPathValue, setFieldPathValue, syncFieldPath } from '../../../ConfigSyncUtil'
import { getFieldI18Name } from '../FieldLabel'

const JSON_ERROR_NONE = 0
const JSON_ERROR_SYNTAX = 1
const JSON_ERROR_ARRAY_REQUIRED = 2
const JSON_ERROR_OBJECT_REQUIRED = 3
const JSON_ERROR_SAVE_FAILED = 4

@ComponentV2
export struct JsonField {
  @Param @Require field: string
  @Param fieldPath: string[] = [this.field]
  @Param isList: boolean = false
  @Consumer("field_edit_enable") enable: boolean = true
  @Local value: string = ''
  @Local error: number = JSON_ERROR_NONE
  @Local isEdit: boolean = false
  private active: boolean = false

  @Computed
  get config(): ConfigJson | undefined {
    return AppManager.easytier.getEditingConfig()
  }

  @Computed
  get statusText(): ResourceStr {
    if (this.error === JSON_ERROR_SYNTAX) {
      return $r('app.string.json_invalid')
    }
    if (this.error === JSON_ERROR_ARRAY_REQUIRED) {
      return $r('app.string.json_array_required')
    }
    if (this.error === JSON_ERROR_OBJECT_REQUIRED) {
      return $r('app.string.json_object_required')
    }
    if (this.error === JSON_ERROR_SAVE_FAILED) {
      return $r('app.string.json_save_failed')
    }
    return $r('app.string.json_format')
  }

  @Computed
  get statusColor(): ResourceColor {
    return this.error === JSON_ERROR_NONE ? $r('sys.color.font_secondary') : $r('sys.color.warning')
  }

  @Computed
  get editorBorderColor(): ResourceColor {
    if (this.error !== JSON_ERROR_NONE) {
      return $r('sys.color.warning')
    }
    if (this.isEdit) {
      return $r('sys.color.brand')
    }
    return this.enable ? $r('sys.color.comp_background_secondary') : $r('sys.color.comp_background_tertiary')
  }

  private formatValue(raw: ConfigFieldValue): string {
    const fallback: ConfigFieldValue = this.isList ? [] : {}
    return JSON.stringify(raw ?? fallback, null, 2)
  }

  aboutToAppear(): void {
    this.active = true
    this.value = this.formatValue(getFieldPathValue(this.config!, this.fieldPath))
  }

  aboutToDisappear(): void {
    this.active = false
    this.value = ''
    this.error = JSON_ERROR_NONE
    this.isEdit = false
  }

  private commit(): void {
    if (!this.enable || !this.active) {
      return
    }
    try {
      const parsed: ConfigFieldValue = JSON.parse(this.value)
      if (this.isList && !Array.isArray(parsed)) {
        this.error = JSON_ERROR_ARRAY_REQUIRED
        return
      }
      if (!this.isList && (parsed === null || typeof parsed !== 'object' || Array.isArray(parsed))) {
        this.error = JSON_ERROR_OBJECT_REQUIRED
        return
      }
      const previous: ConfigFieldValue = getFieldPathValue(this.config!, this.fieldPath)
      setFieldPathValue(this.config!, this.fieldPath, parsed)
      if (!syncFieldPath(this.config!.instance_id!, this.fieldPath, this.config!)) {
        setFieldPathValue(this.config!, this.fieldPath, previous)
        this.error = JSON_ERROR_SAVE_FAILED
        return
      }
      this.value = this.formatValue(parsed)
      this.error = JSON_ERROR_NONE
    } catch (_) {
      this.error = JSON_ERROR_SYNTAX
    }
  }

  build() {
    Column({ space: 8 }) {
      Row() {
        Text(getFieldI18Name(this.field))
          .fontSize(16)
          .fontColor(this.enable ? $r('sys.color.font_primary') : $r('sys.color.font_tertiary'))
        Blank()
        Text(this.statusText)
          .fontSize(12)
          .fontColor(this.statusColor)
      }
      .width('100%')

      TextArea({
        text: this.value,
        placeholder: this.isList ? '[\n]' : '{\n}'
      })
        .width('100%')
        .height(112)
        .type(TextAreaType.NORMAL)
        .fontSize(13)
        .fontColor(this.enable ? $r('sys.color.font_primary') : $r('sys.color.font_tertiary'))
        .backgroundColor(Color.Transparent)
        .padding({ left: 10, right: 10, top: 8, bottom: 8 })
        .borderWidth(2)
        .borderColor(this.editorBorderColor)
        .borderRadius(12)
        .enableAutoFill(false)
        .enabled(this.enable)
        .onChange((text: string) => {
          this.value = text
          this.error = JSON_ERROR_NONE
        })
        .onEditChange((isEdit: boolean) => {
          this.isEdit = isEdit
        })

      Row() {
        Blank()
        Button($r('app.string.json_apply'))
          .fontSize(13)
          .height(36)
          .enabled(this.enable)
          .accessibilityText($r('app.string.json_apply'))
          .onClick(() => {
            this.commit()
          })
      }
      .width('100%')
    }
    .width('100%')
  }
}
