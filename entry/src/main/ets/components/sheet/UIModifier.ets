import { EditableLeftIconType, EditableTitleBar, LengthMetrics } from '@kit.ArkUI'
import { AppManager } from '../../AppManager'
import { EventHelper } from '../../util/EventHelper'

@ComponentV2
export struct UI_Title {
  build() {
    EditableTitleBar({
      leftIconStyle: EditableLeftIconType.Back,
      title: 'UI 设置',
      contentMargin: {
        start: LengthMetrics.vp(0), end: LengthMetrics.vp(0),
      },
      isSaveIconRequired: false,
      onCancel: () => {
        EventHelper.emitterPublish("home_close_sheet")
      }
    })
  }
}

@ComponentV2
export struct UI_Content {
  @Local isPosture: boolean = AppManager.preference.posture_detection

  getLabel(type: string): ResourceStr {
    if (type === 'Instances') {
      return $r('app.string.network_instances')
    } else if (type === 'Logs') {
      return $r('app.string.logging')
    } else if (type === 'Favorite') {
      return $r('app.string.i18_favorite')
    } else if (type === 'SharedPeers') {
      return $r('app.string.peer_info')
    } else if (type === 'QQ') {
      return 'QQ群'
    }
    return type
  }

  getIcon(type: string): Resource {
    if (type === 'Instances') {
      return $r('sys.symbol.key_shield')
    } else if (type === 'Logs') {
      return $r('sys.symbol.list_bullet_square')
    } else if (type === 'Favorite') {
      return $r('sys.symbol.star_fill')
    } else if (type === 'SharedPeers') {
      return $r('sys.symbol.share')
    } else if (type === 'QQ') {
      return $r('sys.symbol.message_on_message')
    }
    return $r('sys.symbol.square')
  }

  build() {
    Column() {
      Row() {
        Column() {
          Text('适人握持')
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
          Text('根据设备握持姿态优化布局，方便单手操作')
            .fontSize(12)
            .fontColor($r('sys.color.font_secondary'))
            .margin({ top: 4 })
        }
        .alignItems(HorizontalAlign.Start)
        Blank()
        Toggle({ type: ToggleType.Switch, isOn: this.isPosture })
          .onChange((isOn) => {
            this.isPosture = isOn
            AppManager.preference.posture_detection = isOn
          })
      }
      .width('100%')
      .padding({
        left: 16,
        right: 16,
        top: 12,
        bottom: 12
      })
      List() {
        ForEach(AppManager.layout.comp_types, (type: string) => {
          ListItem() {
            Row() {
              SymbolGlyph(this.getIcon(type))
                .fontSize(24)
                .fontColor([$r('sys.color.font_primary')])
                .margin({ right: 12 })
              Text(this.getLabel(type))
                .fontSize(16)
                .fontWeight(FontWeight.Regular)
              Blank()
              Toggle({ type: ToggleType.Switch, isOn: AppManager.layout.comp_sequence.includes(type) })
                .onChange((isOn) => {
                  if (isOn) {
                    AppManager.layout.addComponent(type)
                  } else {
                    AppManager.layout.removeComponent(type)
                  }
                })
            }
            .width('100%')
            .padding({
              left: 16,
              right: 16,
              top: 12,
              bottom: 12
            })
          }
        }, (type: string) => type)
      }.width('100%').layoutWeight(1)
    }.height('100%')
  }
}

  