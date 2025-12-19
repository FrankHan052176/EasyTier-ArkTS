import { AppManager } from '../../AppManager'

@ComponentV2
export struct InstanceSelector {
  @Param selectedUuid: string = ""
  @Event onSelect: (uuid: string) => void = () => {}

  @Local newSelectedUuid: string = ""
  @Local isSelecting: boolean = false
  @Local scroller: Scroller = new Scroller()
  
  @Computed
  get uuids() {
    return Array.from(AppManager.data.configUUIDNameMap.keys())
  }

  @Builder
  selector() {
    List({
      scroller: this.scroller,
      initialIndex: this.uuids.indexOf(this.newSelectedUuid)
    }) {
      ForEach(this.uuids, (uuid: string) => {
        ListItem() {
          Row() {
            Text(AppManager.data.configUUIDNameMap.get(uuid) || uuid)
              .fontSize(14)
              .fontColor(uuid === this.newSelectedUuid ? $r("sys.color.brand") : $r("sys.color.font_primary"))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .padding({ left: 12, right: 12 })
          .width('100%')
          .height(40)
          .alignItems(VerticalAlign.Center)
          .justifyContent(FlexAlign.Start)
          .backgroundColor(uuid === this.newSelectedUuid ? $r("sys.color.comp_background_tertiary") : $r("sys.color.background_primary"))
        }
      })
    }
    .listDirection(Axis.Vertical)
    .width(160)
    .height(Math.min(this.uuids.length * 40, 200))
    .scrollBar(BarState.Off)
    .enableScrollInteraction(false)
  }

  build() {
    Column() {
      Column() {
        Text(AppManager.data.configUUIDNameMap.get(this.selectedUuid) || "未选择实例")
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('sys.color.font_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        
        Text("上下滑动切换")
          .fontSize(12)
          .fontColor($r('sys.color.font_secondary'))
          .margin({ top: 4 })
      }
      .width(160)
      .justifyContent(FlexAlign.Center)
    }
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
    .onTouch((event) => {
      if (event.type === TouchType.Down) {
        this.isSelecting = true
      } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
        this.isSelecting = false
      }
    })
    .gesture(
      PanGesture({ direction: PanDirection.Vertical, fingers: 1 })
        .onActionStart(() => {
          this.isSelecting = true
          this.newSelectedUuid = this.selectedUuid
        })
        .onActionUpdate((event: GestureEvent) => {
          const sensitivity = 30
          const deltaIndex = Math.floor(event.offsetY / sensitivity)
          const currentIndex = this.uuids.indexOf(this.selectedUuid)
          let nextIndex = currentIndex + deltaIndex
          nextIndex = Math.max(0, Math.min(this.uuids.length - 1, nextIndex))
          
          if (this.uuids[nextIndex] !== this.newSelectedUuid) {
            this.newSelectedUuid = this.uuids[nextIndex]
            this.scroller.scrollToIndex(nextIndex, true, ScrollAlign.CENTER)
          }
        })
        .onActionEnd(() => {
          this.isSelecting = false
          if (this.newSelectedUuid !== this.selectedUuid) {
            this.onSelect(this.newSelectedUuid)
          }
        })
    )
    .bindPopup(this.isSelecting, {
      builder: this.selector,
      placement: Placement.Right,
      mask: false,
      popupColor: $r("sys.color.background_primary"),
      radius: 12,
      enableArrow: false
    })
  }
}