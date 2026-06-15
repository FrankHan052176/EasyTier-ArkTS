import { AppManager } from '../../../AppManager'
import { ConfigFieldValue, ConfigJson } from '../../../config/schema/SchemaConfig'
import { getFieldPathValue, setFieldPathValue, syncFieldPath } from '../../../ConfigSyncUtil'
import { getFieldI18Name } from '../FieldLabel'

@ComponentV2
export struct UnsupportedField {
  @Param @Require field: string
  @Param fieldPath: string[] = [this.field]
  @Consumer("field_edit_enable") enable: boolean = true
  @Local value: string = ''
  @Local parseError: boolean = false
  private active: boolean = false

  @Computed
  get config(): ConfigJson | undefined {
    return AppManager.easytier.getEditingConfig()
  }

  aboutToAppear(): void {
    this.active = true
    const raw: ConfigFieldValue = getFieldPathValue(this.config!, this.fieldPath)
    this.value = JSON.stringify(raw ?? null)
  }

  aboutToDisappear(): void {
    this.active = false
    this.value = ''
    this.parseError = false
  }

  private commit(): void {
    if (!this.enable || !this.active) {
      return
    }
    try {
      const parsed: ConfigFieldValue = JSON.parse(this.value)
      setFieldPathValue(this.config!, this.fieldPath, parsed)
      syncFieldPath(this.config!.instance_id!, this.fieldPath, this.config!)
      this.parseError = false
    } catch (_) {
      this.parseError = true
    }
  }

  build() {
    Column({ space: 8 }) {
      Row() {
        Text(getFieldI18Name(this.field))
          .fontSize(16)
          .fontColor(this.enable ? $r("sys.color.font_primary") : $r("sys.color.font_tertiary"))
        Blank()
        Text(this.parseError ? 'JSON 无效' : 'JSON')
          .fontSize(12)
          .fontColor(this.parseError ? $r("sys.color.warning") : $r("sys.color.font_secondary"))
      }
      .width('100%')

      Row({ space: 8 }) {
        TextInput({ text: this.value })
          .layoutWeight(1)
          .type(InputType.Normal)
          .enableAutoFill(false)
          .enabled(this.enable)
          .onChange((value: string) => {
            this.value = value
            this.parseError = false
          })
          .onSubmit(() => {
            this.commit()
          })
        SymbolGlyph($r('sys.symbol.checkmark'))
          .fontSize(18)
          .fontColor([this.enable ? $r("sys.color.brand") : $r("sys.color.font_tertiary")])
          .onClick(() => {
            this.commit()
          })
      }
      .width('100%')
      .borderWidth(2)
      .borderColor(this.parseError ? $r("sys.color.warning") : $r("sys.color.comp_background_secondary"))
      .padding({ left: 12, right: 12, top: 8, bottom: 8 })
      .borderRadius(12)
    }
    .width('100%')
  }
}
