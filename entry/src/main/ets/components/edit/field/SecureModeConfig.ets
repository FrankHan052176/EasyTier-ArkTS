import { ContentUtil } from '../../../ContentUtil';
import { AppManager, Sfp2vp, Svp2fp } from '../../../AppManager';
import { flagsCategory, flagsSymbol } from '../../../util/FlagsInfo';

@ComponentV2
export struct SecureModeConfig {
  @Param @Require field: string
  @Consumer('field_width') field_width: number = 0
  @Local enable: boolean = false
  @Local local_private_key: string = ""
  @Local local_public_key: string = ""

  @Computed
  get config() {
    return AppManager.easytier.getEditingConfig()
  }

  @Computed
  get preference() {
    return AppManager.preference.configPreferences.get(AppManager.uiState.editingInstance ?? "")
  }

  aboutToAppear(): void {
    let value: ESObject = this.config![ContentUtil.safeFieldName(this.field)]
    if (value) {
      this.enable = value["enable"] ?? false
      this.local_private_key = value["local_private_key"] ?? ""
      this.local_public_key = value["local_public_key"] ?? ""
    }
  }

  build() {

  }
}