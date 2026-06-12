import { common } from '@kit.AbilityKit'
import { StatusBarPanelClient } from '../services/desktop/StatusBarPanelClient'
import {
  emptyStatusBarPanelState,
  STATUS_BAR_PANEL_ACTION_OPEN_APP,
  STATUS_BAR_PANEL_ACTION_STOP_ALL,
  STATUS_BAR_PANEL_ACTION_TOGGLE_FAVORITE,
  STATUS_BAR_PANEL_SOCKET_NAME,
  StatusBarPanelState
} from '../services/desktop/StatusBarPanelTypes'

@Entry
@Component
struct StatusBarPage {
  private client: StatusBarPanelClient = new StatusBarPanelClient()
  @State panelState: StatusBarPanelState = emptyStatusBarPanelState()
  @State connected: boolean = false

  aboutToAppear(): void {
    const context = this.getUIContext().getHostContext() as common.Context
    const socketPath = `${context.filesDir}/${STATUS_BAR_PANEL_SOCKET_NAME}`
    this.client.connect({
      socketPath,
      logTarget: 'StatusBarPage',
      onState: (state: StatusBarPanelState) => {
        this.panelState = state
      },
      onConnectionChanged: (connected: boolean) => {
        this.connected = connected
      }
    })
  }

  aboutToDisappear(): void {
    this.client.close()
  }

  @Builder
  private Metric(label: string, value: string) {
    Column({ space: 3 }) {
      Text(value)
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('sys.color.font_primary'))
        .maxLines(1)
      Text(label)
        .fontSize(11)
        .fontColor($r('sys.color.font_secondary'))
        .maxLines(1)
    }
    .layoutWeight(1)
    .padding({ top: 8, bottom: 8 })
    .backgroundColor($r('sys.color.comp_background_secondary'))
    .borderRadius(10)
  }

  @Builder
  private ActionButton(text: string, symbol: Resource, enabled: boolean, action: string) {
    Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.NORMAL, role: ButtonRole.NORMAL }) {
      Row({ space: 6 }) {
        SymbolGlyph(symbol)
          .fontSize(17)
          .fontColor([enabled ? $r('sys.color.font_primary') : $r('sys.color.font_secondary')])
        Text(text)
          .fontSize(14)
          .fontColor(enabled ? $r('sys.color.font_primary') : $r('sys.color.font_secondary'))
          .maxLines(1)
      }
      .justifyContent(FlexAlign.Center)
    }
    .height(42)
    .layoutWeight(1)
    .borderRadius(12)
    .enabled(enabled)
    .onClick(() => {
      this.client.sendAction(action)
    })
  }

  build() {
    Column({ space: 12 }) {
      Row() {
        Column({ space: 4 }) {
          Text('EasyTier')
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('sys.color.font_primary'))
          Text(this.connected ? `${this.panelState.keepAliveMode}保活 · ${this.panelState.selectedName}` : '等待主进程')
            .fontSize(12)
            .fontColor($r('sys.color.font_secondary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        SymbolGlyph(this.connected ? $r('sys.symbol.checkmark_circle') : $r('sys.symbol.exclamationmark_circle'))
          .fontSize(22)
          .fontColor([this.connected ? $r('sys.color.interactive_active') : $r('sys.color.font_secondary')])
      }
      .width('100%')

      Row({ space: 8 }) {
        this.Metric('实例', `${this.panelState.configCount}`)
        this.Metric('运行', `${this.panelState.runningCount}`)
      }
      .width('100%')

      Column({ space: 4 }) {
        Text('收藏实例')
          .fontSize(12)
          .fontColor($r('sys.color.font_secondary'))
        Text(this.panelState.favoriteName)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('sys.color.font_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .padding({ top: 8, bottom: 8, left: 10, right: 10 })
      .backgroundColor($r('sys.color.comp_background_secondary'))
      .borderRadius(12)

      Row({ space: 8 }) {
        this.ActionButton(this.panelState.favoriteRunning ? '停止收藏' : '启动收藏',
          this.panelState.favoriteRunning ? $r('sys.symbol.pause_round_triangle_fill') :
            $r('sys.symbol.play_round_triangle_fill'),
          this.connected && this.panelState.favoriteUuid.length > 0, STATUS_BAR_PANEL_ACTION_TOGGLE_FAVORITE)
        this.ActionButton('打开', $r('sys.symbol.house'), this.connected, STATUS_BAR_PANEL_ACTION_OPEN_APP)
      }
      .width('100%')

      this.ActionButton('停止全部', $r('sys.symbol.stop_circle'), this.connected && this.panelState.runningCount > 0,
        STATUS_BAR_PANEL_ACTION_STOP_ALL)
    }
    .height('100%')
    .width('100%')
    .padding(16)
    .backgroundColor($r('sys.color.background_primary'))
  }
}
