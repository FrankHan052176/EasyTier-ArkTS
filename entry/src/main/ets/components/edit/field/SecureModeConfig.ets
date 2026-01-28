import { ContentUtil } from '../../../ContentUtil';
import { AppManager } from '../../../AppManager';
import { SecureModeConfig } from '../../../protobuf/common';

@ComponentV2
export struct SecureModeConfigField {
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
    let value: SecureModeConfig = this.config![ContentUtil.safeFieldName(this.field)]
    if (value) {
      this.enable = value.enabled ?? false
      this.local_private_key = value.local_private_key ?? ""
      this.local_public_key = value.local_public_key ?? ""
    }
  }

  updateConfig() {
    this.config![ContentUtil.safeFieldName(this.field)] = {
      enabled: this.enable,
      local_private_key: this.local_private_key,
      local_public_key: this.local_public_key
    } as SecureModeConfig
    this.preference?.putSync(this.field, this.config![this.field])
    this.preference?.flushSync()
  }

  build() {
    Row() {
      Text("等待更新")
    }.width(this.field_width).padding(20)
  }
}
