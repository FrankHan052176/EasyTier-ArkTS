import { AppManager } from '../../AppManager'
import { EventHelper } from '../../util/EventHelper'
import { Logger } from '../../util/Logger'
import { WindowUtil } from '../../WindowUtil'

interface InstanceEntry {
  uuid: string
  label: string
}

@ComponentV2
export struct InstanceSelector {
  @Param selectedUuid: string = ""
  @Local isSelecting: boolean = false

  @Computed
  get uuids() {
    return AppManager.easytier.getAllConfigIds()
  }

  @Computed
  get entries(): InstanceEntry[] {
    const entries = AppManager.easytier.listStoredConfigs()
    return entries.map((item) => {
      return {
        uuid: item.configId,
        label: item.displayName && item.displayName.length > 0 ? item.displayName : item.configId
      } as InstanceEntry
    })
  }

  @Event onSelect: (uuid: string) => void = () => {}

  aboutToAppear(): void {
    EventHelper.emitterListener("resize_off", () => {
      this.isSelecting = false
    })
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
        ForEach(this.entries, (entry: InstanceEntry) => {
          ListItem() {
            Row() {
              Column() {
                Text(entry.label)
                  .fontSize(16)
                  .fontWeight(entry.uuid === this.selectedUuid ? FontWeight.Bold : FontWeight.Medium)
                  .fontColor(entry.uuid === this.selectedUuid ? $r('sys.color.brand') : $r('sys.color.font_primary'))
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })

                Text(entry.uuid)
                  .fontSize(12)
                  .fontColor($r('sys.color.font_tertiary'))
                  .margin({ top: 4 })
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
              }
              .layoutWeight(1)
              .alignItems(HorizontalAlign.Start)

              if (entry.uuid === this.selectedUuid) {
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
              this.onSelect(entry.uuid)
              this.isSelecting = false
            })
          }
          .swipeAction({ end: this.DeleteAction(entry.uuid) })
        }, (entry: InstanceEntry) => entry.uuid)
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
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('sys.color.font_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Text("点击切换实例")
          .fontSize(12)
          .fontColor($r('sys.color.font_secondary'))
          .margin({ top: 4 })
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
