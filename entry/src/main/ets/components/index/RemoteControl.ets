import { emitter } from '@kit.BasicServicesKit'
import {
  REMOTE_MANAGE_CONNECTION_EVENT,
  REMOTE_MANAGE_SUMMARY_DIRTY_EVENT,
  RemoteManageService
} from '../../services/remote/RemoteManageService'
import { RemoteSummary } from '../../services/remote/RemoteManageTypes'
import { openRemoteControlGated } from '../../services/iap/RemoteControlGate'
import { EventHelper } from '../../util/EventHelper'

@ComponentV2
export struct RemoteControl {
  @Consumer("w") w: number = 1
  @Consumer("h") h: number = 1
  @Local remoteRevision: number = 0

  private remoteChangedCallback: Callback<emitter.EventData> = (_data: emitter.EventData) => {
    this.remoteRevision++
  }

  aboutToAppear(): void {
    EventHelper.emitterListener(REMOTE_MANAGE_CONNECTION_EVENT, this.remoteChangedCallback)
    EventHelper.emitterListener(REMOTE_MANAGE_SUMMARY_DIRTY_EVENT, this.remoteChangedCallback)
  }

  aboutToDisappear(): void {
    EventHelper.emitterOff(REMOTE_MANAGE_CONNECTION_EVENT, this.remoteChangedCallback)
    EventHelper.emitterOff(REMOTE_MANAGE_SUMMARY_DIRTY_EVENT, this.remoteChangedCallback)
  }

  private summary(): RemoteSummary | undefined {
    if (this.remoteRevision < 0) {
      return undefined
    }
    return RemoteManageService.cachedSummary
  }

  private deviceText(): string {
    const summary = this.summary()
    const name = summary?.deviceName ?? RemoteManageService.currentDeviceName
    if (RemoteManageService.connected && name.length > 0) {
      return name
    }
    return '未连接设备'
  }

  private detailText(): string {
    const summary = this.summary()
    if (!RemoteManageService.connected) {
      return '点击连接并管理其他设备'
    }
    return `${summary?.runtime.runningCount ?? 0} 运行 · ${summary?.configs.length ?? 0} 配置`
  }

  private runtimeText(): string {
    const summary = this.summary()
    if (!RemoteManageService.connected) {
      return '待连接'
    }
    const version = summary?.appVersion ?? summary?.coreVersion ?? ''
    return version.length > 0 ? version : (summary?.runtime.runtimeDurationText ?? '已连接')
  }

  /** 跨设备控制为付费能力：与设置页共用统一的权益校验与付费引导入口 */
  private openRemoteControl(): void {
    openRemoteControlGated(this.getUIContext())
  }

  @Builder
  Logo(size: number = 24) {
    SymbolGlyph($r('sys.symbol.local_and_rectangle'))
      .fontSize(size)
      .fontColor([RemoteManageService.connected ? $r('sys.color.interactive_active') : $r('sys.color.font_secondary')])
  }

  @Builder
  StatePill() {
    Text(RemoteManageService.connected ? '已连接' : '待连接')
      .fontSize(10)
      .fontWeight(FontWeight.Medium)
      .fontColor(RemoteManageService.connected ? $r('sys.color.brand_font') : $r('sys.color.font_secondary'))
      .padding({ left: 8, right: 8, top: 4, bottom: 4 })
      .borderRadius(10)
      .backgroundColor(RemoteManageService.connected ? $r('sys.color.brand') :
      $r('sys.color.comp_background_secondary'))
      .maxLines(1)
  }

  @Builder
  Header(showChevron: boolean = true) {
    Row({ space: 8 }) {
      this.Logo()
      Column({ space: 2 }) {
        Text('跨设备控制')
          .fontSize(this.w === 1 ? 13 : 15)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('sys.color.font_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(this.deviceText())
          .fontSize(10)
          .fontColor($r('sys.color.font_secondary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      if (showChevron) {
        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(14)
          .fontColor([$r('sys.color.font_tertiary')])
      }
    }
    .width('100%')
  }

  @Builder
  Size1x1() {
    Column({ space: 8 }) {
      Row() {
        this.Logo()
        Blank()
        this.StatePill()
      }
      .width('100%')

      Column({ space: 4 }) {
        Text('跨设备控制')
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('sys.color.font_primary'))
          .maxLines(1)
        Text(this.runtimeText())
          .fontSize(11)
          .fontColor($r('sys.color.font_secondary'))
          .maxLines(1)
      }
      .layoutWeight(1)
      .width('100%')
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
    }
    .padding(16)
    .width('100%')
    .height('100%')
  }

  @Builder
  Size2x1() {
    Column({ space: 10 }) {
      this.Header()
      Row() {
        Text(this.detailText())
          .fontSize(12)
          .fontColor($r('sys.color.font_secondary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Blank()
        this.StatePill()
      }
      .layoutWeight(1)
      .width('100%')
      .alignItems(VerticalAlign.Bottom)
    }
    .padding(16)
    .width('100%')
    .height('100%')
  }

  @Builder
  Size1x2() {
    Column({ space: 10 }) {
      this.Header(false)
      Column({ space: 6 }) {
        Text(this.detailText())
          .fontSize(12)
          .fontColor($r('sys.color.font_secondary'))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(this.runtimeText())
          .fontSize(11)
          .fontColor($r('sys.color.font_tertiary'))
          .maxLines(1)
      }
      .layoutWeight(1)
      .width('100%')
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Start)
      Row() {
        this.StatePill()
        Blank()
        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(14)
          .fontColor([$r('sys.color.font_tertiary')])
      }
      .width('100%')
    }
    .padding(16)
    .width('100%')
    .height('100%')
  }

  @Builder
  Size2x2() {
    Column({ space: 12 }) {
      this.Header()
      Row({ space: 8 }) {
        Column({ space: 2 }) {
          Text('运行')
            .fontSize(10)
            .fontColor($r('sys.color.font_secondary'))
          Text((this.summary()?.runtime.runningCount ?? 0).toString())
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('sys.color.font_primary'))
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        Column({ space: 2 }) {
          Text('配置')
            .fontSize(10)
            .fontColor($r('sys.color.font_secondary'))
          Text((this.summary()?.configs.length ?? 0).toString())
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('sys.color.font_primary'))
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
      }
      .layoutWeight(1)
      .width('100%')
      .alignItems(VerticalAlign.Center)
      Text(this.runtimeText())
        .fontSize(11)
        .fontColor($r('sys.color.font_secondary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .padding(16)
    .width('100%')
    .height('100%')
  }

  build() {
    Stack() {
      if (this.w === 1 && this.h === 1) {
        this.Size1x1()
      } else if (this.w === 2 && this.h === 1) {
        this.Size2x1()
      } else if (this.w === 1 && this.h === 2) {
        this.Size1x2()
      } else {
        this.Size2x2()
      }
    }
    .width('100%')
    .height('100%')
    .borderRadius(18)
    .backgroundColor($r("sys.color.comp_background_primary"))
    .shadow({
      radius: 7,
      color: '#09000000'
    })
    .onClick(() => this.openRemoteControl())
  }
}
