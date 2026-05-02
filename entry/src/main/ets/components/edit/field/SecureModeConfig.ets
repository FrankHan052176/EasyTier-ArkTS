import { AppManager } from '../../../AppManager';
import { syncTopLevelField } from '../../../ConfigSyncUtil';

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

  aboutToAppear(): void {
    let value = this.config![this.field] as ESObject | undefined
    if (value) {
      this.enable = value.enabled ?? false
      this.local_private_key = value.local_private_key ?? ""
      this.local_public_key = value.local_public_key ?? ""
    }
  }

  updateConfig() {
    this.config![this.field] = {
      enabled: this.enable,
      local_private_key: this.local_private_key,
      local_public_key: this.local_public_key
    } as ESObject
    syncTopLevelField(this.config!.instance_id!, this.field, this.config!)
  }

  build() {
    Row() {
      Text("等待更新")
    }.width(this.field_width).padding(20)
  }
}
