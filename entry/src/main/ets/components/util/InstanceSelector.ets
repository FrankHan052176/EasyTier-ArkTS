import { AppManager } from '../../AppManager'
import { EventHelper } from '../../util/EventHelper'
import { Logger } from '../../shared/logging/Logger'
import { WindowUtil } from '../../WindowUtil'

interface InstanceEntry {
  uuid: string
  label: string
}

@ComponentV2
export struct InstanceSelector {
  @Param selectedUuid: string = ""
  @Param compact: boolean = false
  @Local isSelecting: boolean = false

  @Computed
  get entries(): InstanceEntry[] {
    return AppManager.data.configIds.map((uuid) => {
      return {
        uuid,
        label: AppManager.easytier.getConfigLabel(uuid, uuid)
      } as InstanceEntry
    })
  }

  @Event onSelect: (uuid: string) => void = () => {}
  private resizeOffCallback = () => {
    this.isSelecting = false
  }

  aboutToAppear(): void {
    EventHelper.emitterListener("resize_off", this.resizeOffCallback)
  }

  aboutToDisappear(): void {
    EventHelper.emitterOff("resize_off", this.resizeOffCallback)
    this.isSelecting = false
  }

  @Builder
  DeleteAction(uuid: string) {
    Row() {
      Button({ type: ButtonType.Circle }) {
        SymbolGlyph($r('sys.symbol.trash'))
          .fontSize(22)
          .fontColor([Color.White])
      }
      .width(40)
      .height(40)
      .backgroundColor($r('sys.color.warning'))
      .onClick(() => {
        AppManager.data.delConfig(uuid)
      })
    }
    .justifyContent(FlexAlign.Center)
    .padding({ left: 10 })
  }

  @Builder
  ModalView() {
    Column() {
      // Title Bar
      Row() {
        Text("实例列表")
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('sys.color.font_primary'))

        Blank()

        Button({ type: ButtonType.Circle, stateEffect: true }) {
          SymbolGlyph($r('sys.symbol.xmark'))
            .fontSize(24)
            .fontColor([$r('sys.color.font_secondary')])
        }
        .width(40)
        .height(40)
        .backgroundColor($r('sys.color.comp_background_tertiary'))
        .onClick(() => {
          this.isSelecting = false
        })
      }
      .width('100%')
      .padding({
        top: 16,
        bottom: 16,
        left: 24,
        right: 24
      })
      .alignItems(VerticalAlign.Center)

      // List
      List({ space: 12 }) {
        ForEach(AppManager.data.configIds, (uuid: string) => {
          ListItem() {
            Row() {
              Column() {
                Text(AppManager.easytier.getConfigLabel(uuid, uuid))
                  .fontSize(16)
                  .fontWeight(uuid === this.selectedUuid ? FontWeight.Bold : FontWeight.Medium)
                  .fontColor(uuid === this.selectedUuid ? $r('sys.color.brand') : $r('sys.color.font_primary'))
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })

                Text(uuid)
                  .fontSize(12)
                  .fontColor($r('sys.color.font_tertiary'))
                  .margin({ top: 4 })
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
              }
              .layoutWeight(1)
              .alignItems(HorizontalAlign.Start)

              if (uuid === this.selectedUuid) {
                SymbolGlyph($r('sys.symbol.checkmark'))
                  .fontSize(24)
                  .fontColor([$r('sys.color.brand')])
                  .margin({ left: 12 })
              }
            }
            .width('100%')
            .padding(16)
            .backgroundColor($r('sys.color.comp_background_tertiary'))
            .borderRadius(16)
            .onClick(() => {
              this.onSelect(uuid)
              this.isSelecting = false
            })
          }
          .swipeAction({ end: this.DeleteAction(uuid) })
        }, (uuid: string) => uuid)
      }
      .width('100%')
      .layoutWeight(1)
      .padding({ left: 16, right: 16 })
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r("sys.color.comp_background_primary"))
    .padding({ top: WindowUtil.statusBarHeight })
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
  }

  build() {
    Column() {
      Column() {
        Text(this.entries.find((item) => item.uuid === this.selectedUuid)?.label ?? "未选择实例")
          .fontSize(this.compact ? 15 : 20)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('sys.color.font_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Text("点击切换实例")
          .fontSize(this.compact ? 10 : 12)
          .fontColor($r('sys.color.font_secondary'))
          .margin({ top: this.compact ? 1 : 4 })
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
    }
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
    .onClick(() => {
      this.isSelecting = true
    })
    .bindContentCover(this.isSelecting!!, this.ModalView(), {
      modalTransition: ModalTransition.DEFAULT,
      backgroundColor: $r("sys.color.comp_background_primary")
    })
  }
}
