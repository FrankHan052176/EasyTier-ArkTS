import { LengthMetrics } from '@kit.ArkUI'
import { AppManager } from '../../AppManager'
import { CLOUD_CONFIG_CHANGED_EVENT } from '../../ConfigSyncUtil'
import { isCloudResetting } from '../../services/cloud/CloudMutationGate'
import { EventHelper } from '../../util/EventHelper'
import easytier from 'easytier-ohrs'

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
  @Computed
  get instanceName() {
    return AppManager.uiState.editingInstance ? (AppManager.easytier.getConfigName(AppManager.uiState.editingInstance) ?? "N/A") : "N/A"
  }

  build() {
    Column() {
      Row() {
        TextInput({ text: this.instanceName })
          .underline()
          .width('80%')
          .onChange((value: string) => {
            if (value.length > 0) {
              if (AppManager.uiState.editingInstance && !isCloudResetting()) {
                easytier.renameStoredConfig(AppManager.uiState.editingInstance, value)
                EventHelper.emitterPublish(CLOUD_CONFIG_CHANGED_EVENT)
              }
            }
          })
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)

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
