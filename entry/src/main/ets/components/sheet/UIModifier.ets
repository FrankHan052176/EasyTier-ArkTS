import { AppManager } from '../../AppManager'
import { EventHelper } from '../../util/EventHelper'
import { LayoutManager } from '../layout/desktop/DesktopGridLayout'

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
        .width('62%')
        .height(48)
        .padding({ left: 12, right: 12 })
        .alignItems(VerticalAlign.Center)
        .hitTestBehavior(HitTestMode.Transparent)
        .zIndex(2)

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
        .width('62%')
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
    .height(64)
    .clip(true)
  }
}

@Builder
function uiGroupHeader(title: string) {
  Text(title)
    .width('100%')
    .fontSize(14)
    .fontColor($r('sys.color.font_secondary'))
    .padding({ top: 10, left: 5, bottom: 3 })
}

@Builder
function uiSwitchRow(symbol: Resource, title: string, subtitle: string, isOn: boolean,
  onChange: (isOn: boolean) => void) {
  ListItem() {
    Row() {
      Row() {
        SymbolGlyph(symbol)
          .fontSize(20)
          .fontColor([$r('sys.color.font_primary')])
          .margin({ right: 10 })
        Column() {
          Text(title)
            .fontSize(16)
            .fontColor($r('sys.color.font_primary'))
            .fontWeight(FontWeight.Medium)
            .maxLines(1)
          Text(subtitle)
            .fontSize(12)
            .fontColor($r('sys.color.font_secondary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .margin({ top: 3 })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
      }
      .layoutWeight(1)

      Toggle({ type: ToggleType.Switch, isOn: isOn })
        .selectedColor($r('sys.color.brand'))
        .switchPointColor($r('sys.color.comp_background_list_card'))
        .height(29)
        .width(52)
        .onChange(onChange)
    }
    .width('100%')
    .height(64)
    .padding({ left: 12, right: 10, top: 8, bottom: 8 })
    .borderRadius(18)
    .backgroundColor($r('sys.color.comp_background_primary'))
    .shadow({
      radius: 7,
      color: '#1F000000'
    })
    .alignItems(VerticalAlign.Center)
    .justifyContent(FlexAlign.SpaceBetween)
  }
  .margin({ bottom: 10 })
}

@Builder
function postureSwitchCard(isOn: boolean, onChange: (isOn: boolean) => void) {
  ListItem() {
    Column() {
      Row() {
        Row() {
          SymbolGlyph($r('sys.symbol.hand_thumbsup_fill'))
            .fontSize(20)
            .fontColor([$r('sys.color.font_primary')])
            .margin({ right: 10 })
          Column() {
            Text('适人握持')
              .fontSize(16)
              .fontColor($r('sys.color.font_primary'))
              .fontWeight(FontWeight.Medium)
              .maxLines(1)
            Text('单手布局优化')
              .fontSize(12)
              .fontColor($r('sys.color.font_secondary'))
              .maxLines(1)
              .margin({ top: 3 })
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
        }
        .layoutWeight(1)

        Toggle({ type: ToggleType.Switch, isOn: isOn })
          .selectedColor($r('sys.color.brand'))
          .switchPointColor($r('sys.color.comp_background_list_card'))
          .height(29)
          .width(52)
          .onChange(onChange)
      }
      .height(52)
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Divider()
        .strokeWidth(1)
        .opacity(0.1)
        .color($r('sys.color.font_secondary'))
        .margin({ left: 30, right: 30 })

      PostureDemo()
        .margin({ top: 6 })
    }
    .width('100%')
    .padding({ left: 12, right: 10, top: 8, bottom: 12 })
    .borderRadius(18)
    .backgroundColor($r('sys.color.comp_background_primary'))
    .shadow({
      radius: 7,
      color: '#1F000000'
    })
  }
  .margin({ bottom: 10 })
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

  @Builder
  componentRow(type: string) {
    ListItem() {
      Row() {
        SymbolGlyph(this.getIcon(type))
          .fontSize(22)
          .fontColor([$r('sys.color.font_primary')])
          .margin({ right: 12 })

        Column() {
          Text(this.getLabel(type))
            .fontSize(16)
            .fontColor($r('sys.color.font_primary'))
            .fontWeight(FontWeight.Medium)
            .maxLines(1)
          Text(this.layout!.comp_sequence.includes(type) ? '显示在主页' : '已隐藏')
            .fontSize(12)
            .fontColor($r('sys.color.font_secondary'))
            .maxLines(1)
            .margin({ top: 3 })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

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
      .height(64)
      .padding({ left: 12, right: 10, top: 8, bottom: 8 })
      .borderRadius(18)
      .backgroundColor($r('sys.color.comp_background_primary'))
      .shadow({
        radius: 7,
        color: '#1F000000'
      })
      .alignItems(VerticalAlign.Center)
      .justifyContent(FlexAlign.SpaceBetween)
    }
    .margin({ bottom: 10 })
  }

  build() {
    List() {
      ListItem()
        .height(64)

      ListItemGroup({ header: uiGroupHeader('布局') }) {
        postureSwitchCard(this.isPosture, (isOn: boolean) => {
            this.isPosture = isOn
            AppManager.uiState.holding_detector = isOn
            if (!isOn) {
              EventHelper.emitterPublish('reset_holding_detector')
            }
          })
      }

      ListItemGroup({ header: uiGroupHeader('隐私') }) {
        uiSwitchRow($r('sys.symbol.lock_fill'), '隐私模式', '编辑配置时遮罩敏感信息',
          AppManager.uiState.vault_mode, (isOn: boolean) => {
            AppManager.uiState.vault_mode = isOn
          })
      }

      if (this.layout) {
        ListItemGroup({ header: uiGroupHeader('主页组件') }) {
          ForEach(this.layout.comp_types, (type: string) => {
            this.componentRow(type)
          }, (type: string) => type)
        }
      }

      ListItem()
        .height(100)
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Off)
    .padding({ left: 15, right: 15, bottom: 12 })
  }
}
