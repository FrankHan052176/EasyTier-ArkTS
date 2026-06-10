import { LengthMetrics } from '@kit.ArkUI'
import { AppManager } from '../../AppManager'
import { CLOUD_CONFIG_CHANGED_EVENT } from '../../ConfigSyncUtil'
import { isCloudResetting } from '../../services/cloud/CloudMutationGate'
import { EventHelper } from '../../util/EventHelper'
import easytier from 'easytier-ohrs'
import {
  getEditingConfigStoreRef,
  getStoredConfigName,
  isEditingRemoteConfig
} from '../../services/config/storage/StoredConfigService'
import { RemoteManageService } from '../../services/remote/RemoteManageService'
import { sendToast } from '../../ToastUtil'

@Extend(Text)
function tips() {
  .width('100%')
  .fontSize(14)
  .fontColor($r("sys.color.font_secondary"))
  .textAlign(TextAlign.Center)
}

@Extend(TextInput)
function underline(textAlign: TextAlign = TextAlign.Center) {
  .padding({
    left: 1,
    right: 1,
    top: 5,
    bottom: 5
  })
  .backgroundColor(Color.Transparent)
  .border({
    width: {
      start: LengthMetrics.vp(0),
      end: LengthMetrics.vp(0),
      top: LengthMetrics.vp(0),
      bottom: LengthMetrics.vp(1)
    },
    color: {
      bottom: $r("sys.color.comp_divider")
    },
    radius: {
      bottomStart: LengthMetrics.vp(0),
      bottomEnd: LengthMetrics.vp(0)
    },
    style: {
      bottom: BorderStyle.Solid
    }
  })
  .textAlign(textAlign)
}

@ComponentV2
export struct Rename_Content {
  @Local draftName: string = ''
  @Local submitting: boolean = false
  private closeAfterSubmit: boolean = false

  @Computed
  get instanceName() {
    return AppManager.uiState.editingInstance ? (getStoredConfigName(AppManager.uiState.editingInstance) ?? "N/A") : "N/A"
  }

  aboutToAppear(): void {
    this.draftName = this.instanceName
  }

  private closeSheet(): void {
    EventHelper.emitterPublish('edit_close_sheet')
  }

  private async commitName(closeAfter: boolean = true): Promise<void> {
    if (this.submitting) {
      if (closeAfter) {
        this.closeAfterSubmit = true
      }
      return
    }
    const instanceId = AppManager.uiState.editingInstance
    const value = this.draftName.trim()
    if (!instanceId || value.length === 0 || value === this.instanceName) {
      if (closeAfter) {
        this.closeSheet()
      }
      return
    }
    this.submitting = true
    this.closeAfterSubmit = closeAfter
    try {
      if (isEditingRemoteConfig()) {
        const ok = await RemoteManageService.renameConfig(instanceId, value, getEditingConfigStoreRef().remoteSessionId)
        if (!ok) {
          sendToast('远端重命名失败', $r('sys.symbol.exclamationmark_circle'), 1)
          return
        }
      } else if (!isCloudResetting()) {
        easytier.renameStoredConfig(instanceId, value)
        EventHelper.emitterPublish(CLOUD_CONFIG_CHANGED_EVENT)
      }
      if (this.closeAfterSubmit) {
        this.closeSheet()
      }
    } catch (error) {
      sendToast(`重命名失败：${(error as Error).message}`, $r('sys.symbol.exclamationmark_circle'), 1)
    } finally {
      this.submitting = false
      this.closeAfterSubmit = false
    }
  }

  build() {
    Column() {
      Row() {
        TextInput({ text: this.draftName })
          .underline()
          .width('80%')
          .onChange((value: string) => {
            this.draftName = value
          })
          .onBlur(() => {
            this.commitName(false)
          })
          .onSubmit(() => {
            this.commitName(true)
          })
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)

      Button('完成', { type: ButtonType.Normal, buttonStyle: ButtonStyleMode.EMPHASIZED, role: ButtonRole.NORMAL })
        .width('80%')
        .borderRadius(13)
        .enabled(!this.submitting)
        .margin({ top: 18 })
        .onClick(() => this.commitName(true))

      Text(`
请设置网络名
      `)
        .tips()
      Blank()
        .width('100%')
        .height(100)
    }
    .width('90%')
  }
}
