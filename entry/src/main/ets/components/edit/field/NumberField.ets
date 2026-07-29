import { hasFieldTag } from '../../../config/fields/ConfigFieldUi';
import { getFieldI18Name } from '../FieldLabel';
import { AppManager } from '../../../AppManager';
import { getFieldPathValue, setFieldPathValue, syncFieldPath } from '../../../ConfigSyncUtil';

const INSTANCE_RECV_BPS_LIMIT_FIELD = 'instance_recv_bps_limit'
const UINT64_MAX_DECIMAL = '18446744073709551615'
const MAX_SAFE_INTEGER_DECIMAL = '9007199254740991'

function normalizedUnsignedDecimal(value: string): string {
  let index = 0
  while (index < value.length - 1 && value.charAt(index) === '0') {
    index++
  }
  return value.substring(index)
}

function isUnsignedDecimal(value: string): boolean {
  if (value.length === 0) {
    return false
  }
  for (let index = 0; index < value.length; index++) {
    const code = value.charCodeAt(index)
    if (code < 48 || code > 57) {
      return false
    }
  }
  return true
}

function decimalLessThanOrEqual(value: string, maximum: string): boolean {
  if (value.length !== maximum.length) {
    return value.length < maximum.length
  }
  return value <= maximum
}

@Extend(TextInput)
function fieldTextInput(widthValue: number, maxLengthValue: number) {
  .padding(0)
  .borderRadius(0)
  .width(widthValue)
  .type(InputType.Number)
  .maxLength(maxLengthValue)
  .backgroundColor(Color.Transparent)
  .textAlign(TextAlign.Center)
  .enableAutoFill(false)
}

@ComponentV2
export struct NumberField {
  @Param @Require field: string;
  @Param fieldPath: string[] = [this.field]
  @Consumer("field_edit_enable") enable: boolean = true
  @Local value: string = "" + (getFieldPathValue(this.config!, this.fieldPath) ?? "");
  @Local intensity: number = 0;
  @Local offsetX: number = 0;
  @Local isEdit: boolean = false;
  @Local invalid: boolean = false;
  private active: boolean = false

  @Computed
  get hasTitle() {
    return hasFieldTag(this.field, "topFieldName")
  }

  @Computed
  get config() {
    return AppManager.easytier.getEditingConfig()
  }

  @Computed
  get fontColor() {
    return this.enable ? $r("sys.color.font_primary") : $r("sys.color.font_tertiary")
  }

  @Computed
  get isInstanceRecvBpsLimit() {
    return this.field === INSTANCE_RECV_BPS_LIMIT_FIELD
  }

  @Computed
  get inputWidth() {
    return this.isInstanceRecvBpsLimit ? 156 : 72
  }

  @Computed
  get inputMaxLength() {
    return this.isInstanceRecvBpsLimit ? 20 : 12
  }

  @Computed
  get placeholder(): ResourceStr {
    return this.isInstanceRecvBpsLimit ? $r('app.string.instance_recv_bps_limit_placeholder') : ''
  }

  private updateFromConfig(): void {
    if (!this.isEdit) {
      this.value = "" + (getFieldPathValue(this.config!, this.fieldPath) ?? "")
    }
  }

  aboutToAppear(): void {
    this.active = true
    this.updateFromConfig()
  }

  aboutToDisappear(): void {
    this.active = false
    this.isEdit = false
    this.invalid = false
    this.value = ''
  }

  private commitValue(value: string | number | undefined): void {
    setFieldPathValue(this.config!, this.fieldPath, value)
    syncFieldPath(this.config!.instance_id!, this.fieldPath, this.config!)
  }

  private changeInstanceRecvBpsLimit(value: string): void {
    const trimmed = value.trim()
    if (trimmed.length === 0) {
      this.value = ''
      this.invalid = false
      this.commitValue(undefined)
      return
    }
    if (!isUnsignedDecimal(trimmed)) {
      this.invalid = true
      return
    }
    const normalized = normalizedUnsignedDecimal(trimmed)
    if (!decimalLessThanOrEqual(normalized, UINT64_MAX_DECIMAL)) {
      this.invalid = true
      return
    }
    if (normalized === '0') {
      this.value = ''
      this.invalid = false
      this.commitValue(undefined)
      return
    }
    this.invalid = false
    if (decimalLessThanOrEqual(normalized, MAX_SAFE_INTEGER_DECIMAL)) {
      this.commitValue(Number.parseInt(normalized))
    } else {
      // protobuf JSON 用十进制字符串无损承载超过 JS 安全整数的 uint64。
      this.commitValue(normalized)
    }
  }

  private change(value: string): void {
    if (!this.active) {
      return
    }
    this.value = value
    if (this.isInstanceRecvBpsLimit) {
      this.changeInstanceRecvBpsLimit(value)
      return
    }
    this.invalid = false
    if (value.length === 0) {
      this.commitValue(undefined)
      return
    }
    const numberValue = Number.parseInt(value)
    this.commitValue(Number.isNaN(numberValue) ? 0 : numberValue)
  }

  build() {
    Row() {
      Text(getFieldI18Name(this.field))
        .focusable(false)
      Row({ space: 6 }) {
        TextInput({ text: this.value!!, placeholder: this.placeholder })
          .fieldTextInput(this.inputWidth, this.inputMaxLength)
          .onChange((value) => this.change(value))
          .fontColor(this.fontColor)
          .enabled(this.enable)
          .onEditChange((isEdit) => {
            this.isEdit = isEdit
          })
        if (this.isInstanceRecvBpsLimit) {
          Text('B/s')
            .fontSize(12)
            .fontColor(this.fontColor)
        }
      }
      .borderWidth(2)
      .borderColor(this.invalid ? $r('sys.color.warning') : (this.isEdit ? $r("sys.color.brand") :
        (this.enable ? $r("sys.color.comp_background_secondary") : $r("sys.color.comp_background_tertiary")))
      )
      .padding({
        left: 12,
        right: 12,
        top: 8,
        bottom: 8
      })
      .borderRadius(12)
      .animation({
        curve: Curve.Ease,
        duration: 300
      })
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .justifyContent(FlexAlign.SpaceBetween)
  }
}
