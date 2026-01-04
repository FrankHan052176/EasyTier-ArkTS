import { curves } from '@kit.ArkUI';
import { ContentUtil } from '../../../ContentUtil';
import { getFieldI18Name } from '../FieldEdit';
import { AppManager, Svp2fp } from '../../../AppManager';

@ComponentV2
export struct EnableField {
  @Param @Require field: string;
  @Consumer("field_edit_enable") enable: boolean = true
  @Local button: boolean = true;

  @Computed
  get config() {
    return AppManager.easytier.getEditingConfig()
  }

  @Computed
  get preference() {
    return AppManager.preference.configPreferences.get(AppManager.data.editingInstance ?? "")
  }

  @Computed
  get hasTitle() {
    return ContentUtil.hasTag(this.field, "rightFieldName")
  }

  @Computed
  get isInverse() {
    return ContentUtil.hasTag(this.field, "inverse")
  }

  aboutToAppear(): void {
    this.button = this.config![ContentUtil.safeFieldName(this.field)] ?? false
    this.updateEnable()
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
      this.config![ContentUtil.safeFieldName(this.field)] = this.button
      this.preference?.putSync(this.field, this.config![this.field])
      this.preference?.flushSync()
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