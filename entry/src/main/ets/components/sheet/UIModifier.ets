import { EditableLeftIconType, EditableTitleBar, LengthMetrics } from '@kit.ArkUI'
import { AppManager } from '../../AppManager'
import { EventHelper } from '../../util/EventHelper'
import { LayoutManager } from 'desktop_layout'

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
struct PostureDemo {
  @Local alignItem: FlexAlign = FlexAlign.Center
  @Local leftHandOpacity: number = 0
  @Local rightHandOpacity: number = 0
  private timer: number = -1

  aboutToAppear() {
    let step = 0
    this.timer = setInterval(() => {
      step++
      animateTo({ duration: 600, curve: Curve.FastOutSlowIn }, () => {
        if (step % 4 === 0) {
          this.alignItem = FlexAlign.Center
          this.leftHandOpacity = 0
          this.rightHandOpacity = 0
        } else if (step % 4 === 1) {
          this.alignItem = FlexAlign.Start
          this.leftHandOpacity = 1
          this.rightHandOpacity = 0
        } else if (step % 4 === 2) {
          this.alignItem = FlexAlign.Center
          this.leftHandOpacity = 0
          this.rightHandOpacity = 0
        } else if (step % 4 === 3) {
          this.alignItem = FlexAlign.End
          this.leftHandOpacity = 0
          this.rightHandOpacity = 1
        }
      })
    }, 2000)
  }

  aboutToDisappear() {
    clearInterval(this.timer)
  }

  build() {
    Column() {
      Stack() {
        // Hands simulation
        Row() {
          if (this.leftHandOpacity === 1) {
            SymbolGlyph($r('sys.symbol.hand_thumbsup_fill'))
              .fontSize(40)
              .fontColor([$r('sys.color.font_secondary')])
              .offset({ x: -40, y: 10 })
              .transition(TransitionEffect.move(TransitionEdge.BOTTOM))
          }
          Blank()
          if (this.rightHandOpacity === 1) {
            SymbolGlyph($r('sys.symbol.hand_thumbsup_fill'))
              .fontSize(40)
              .fontColor([$r('sys.color.font_secondary')])
              .scale({ x: -1, y: 1 })
              .offset({ x: 40, y: 10 })
              .transition(TransitionEffect.move(TransitionEdge.BOTTOM))
          }
        }
        .width('40%')
        .height(48)
        .padding({ left: 12, right: 12 })
        .alignItems(VerticalAlign.Center)
        .hitTestBehavior(HitTestMode.Transparent)
        .zIndex(2)

        // Bar container
        Row() {
          Row() {
            Circle({ width: 8, height: 8 }).fill($r('sys.color.font_tertiary'))
            Circle({ width: 12, height: 12 }).fill($r('sys.color.brand')).margin({ left: 8, right: 8 })
            Circle({ width: 8, height: 8 }).fill($r('sys.color.font_tertiary'))
          }
          .height(28)
          .padding({ left: 12, right: 12 })
          .backgroundColor($r('sys.color.interactive_select'))
          .borderRadius(14)
          .shadow(ShadowStyle.OUTER_DEFAULT_XS)
        }
        .width('40%')
        .justifyContent(this.alignItem)
        .height(48)
        .backgroundColor($r('sys.color.background_tertiary'))
        .borderRadius(12)
        .padding({ left: 12, right: 12 })
        .alignItems(VerticalAlign.Center)
        .zIndex(1)
      }
    }
    .width('100%')
    .padding({
      left: 16,
      right: 16,
      top: 12,
      bottom: 12
    })
    .clip(true)
  }
}

@ComponentV2
export struct UI_Content {
  @Local isPosture: boolean = AppManager.uiState.holding_detector

  @Computed
  get layout() {
    return LayoutManager.getLayout("home")
  }

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
      PostureDemo()
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
          .selectedColor($r('sys.color.brand'))
          .switchPointColor($r('sys.color.comp_background_list_card'))
          .height(29)
          .width(52)
          .onChange((isOn) => {
            this.isPosture = isOn
            AppManager.uiState.holding_detector = isOn
            if (!isOn) {
              EventHelper.emitterPublish("reset_holding_detector")
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
      Divider()
        .strokeWidth(1)
        .opacity(0.1)
        .color($r('sys.color.font_secondary'))
        .padding({ left: 16, right: 16 })
      Row() {
        Column() {
          Text('隐私模式')
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
          Text('编辑配置时将遮罩部分隐私信息')
            .fontSize(12)
            .fontColor($r('sys.color.font_secondary'))
            .margin({ top: 4 })
        }
        .alignItems(HorizontalAlign.Start)

        Blank()
        Toggle({ type: ToggleType.Switch, isOn: AppManager.uiState.vault_mode })
          .selectedColor($r('sys.color.brand'))
          .switchPointColor($r('sys.color.comp_background_list_card'))
          .height(29)
          .width(52)
          .onChange((isOn) => {
            AppManager.uiState.vault_mode = isOn
          })
      }
      .width('100%')
      .padding({
        left: 16,
        right: 16,
        top: 12,
        bottom: 12
      })
      Divider()
        .strokeWidth(1)
        .opacity(0.1)
        .color($r('sys.color.font_secondary'))
        .padding({ left: 16, right: 16 })
      Text('组件管理')
        .fontSize(14)
        .fontColor($r('sys.color.font_secondary'))
        .width('100%')
        .padding({ left: 16, top: 12, bottom: 4 })
      if (this.layout) {
        List() {
          ForEach(this.layout.comp_types, (type: string) => {
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
                Toggle({ type: ToggleType.Switch, isOn: this.layout!.comp_sequence.includes(type) })
                  .selectedColor($r('sys.color.brand'))
                  .switchPointColor($r('sys.color.comp_background_list_card'))
                  .height(29)
                  .width(52)
                  .onChange((isOn) => {
                    if (isOn) {
                      this.layout!.addComponent(type)
                    } else {
                      this.layout!.removeComponent(type)
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
      }
    }.height('100%')
  }
}

  