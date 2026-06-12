import { curves } from '@kit.ArkUI';
import { hasFieldTag } from '../../../config/fields/ConfigFieldUi';
import { getFieldI18Name } from '../FieldLabel';
import { AppManager, Svp2fp } from '../../../AppManager';
import { getFieldPathValue, setFieldPathValue, syncFieldPath } from '../../../ConfigSyncUtil';

@ComponentV2
export struct EnableField {
  @Param @Require field: string;
  @Param fieldPath: string[] = [this.field]
  @Consumer("field_edit_enable") enable: boolean = true
  @Local button: boolean = true;

  @Computed
  get config() {
    return AppManager.easytier.getEditingConfig()
  }

  @Computed
  get hasTitle() {
    return hasFieldTag(this.field, "rightFieldName")
  }

  @Computed
  get isInverse() {
    return hasFieldTag(this.field, "inverse")
  }

  private updateFromConfig(): void {
    this.button = (getFieldPathValue(this.config!, this.fieldPath) as boolean) ?? false
    this.updateEnable()
  }

  aboutToAppear(): void {
    this.updateFromConfig()
  }

  aboutToDisappear(): void {
    this.button = false
  }

  updateEnable() {
    this.enable = this.isInverse ? !this.button : this.button
  }

  click(isOn: boolean) {
    animateToImmediately({
      curve: Curve.FastOutSlowIn,
      duration: 300
    }, () => {
      this.button = isOn
      setFieldPathValue(this.config!, this.fieldPath, this.button)
      syncFieldPath(this.config!.instance_id!, this.fieldPath, this.config!)
    })
    animateToImmediately({
      curve: curves.springMotion(0.4, 0.7),
      duration: 300
    }, () => {
      this.updateEnable()
    })
  }

  build() {
    Row() {
      Toggle({ type: ToggleType.Switch, isOn: this.button!! })
        .height(20)
        .onChange((isOn: boolean) => {
          this.click(isOn)
        })
      if (this.hasTitle) {
        Text(getFieldI18Name(this.field))
          .fontSize(Svp2fp(20) * 0.7)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.button ? $r("sys.color.brand") : $r("sys.color.font_primary"))
          .margin({ left: 5 })
      }
    }
  }
}
