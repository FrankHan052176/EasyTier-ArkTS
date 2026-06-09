import { Protocol, protocolBGColor, protocolColor } from '../../util/Conversion'
import { WindowUtil } from '../../WindowUtil'

@ComponentV2
export struct ProtocolSelector {
  @Param @Require protocols: Protocol[]
  @Param @Require selected: Protocol
  @Local newSelected: Protocol = this.selected
  @Event onChange: (protocol: Protocol) => void
  @Param comp_width: number = 75
  @Local isSelecting: boolean = false
  @Local scroller: Scroller = new Scroller()
  @Local scrollerMoveTimer: number = 0
  @Local comp_height: number = 0

  private clearMoveTimer(): void {
    if (this.scrollerMoveTimer !== 0) {
      clearInterval(this.scrollerMoveTimer)
      this.scrollerMoveTimer = 0
    }
  }

  aboutToDisappear(): void {
    this.clearMoveTimer()
    this.isSelecting = false
  }

  @Computed
  get scrollWidth() {
    let availableWidth = Math.floor(WindowUtil.width * 0.85)
    let n = Math.min(Math.floor(availableWidth / this.comp_width), this.selectorProtocols.length)
    return n * this.comp_width
  }

  @Computed
  get otherProtocols() {
    return Array.from(this.protocols).filter((value) => {
      return value !== this.selected
    }).reverse()
  }

  @Computed
  get selectorProtocols() {
    return [...this.otherProtocols, this.selected]
  }

  @Builder
  selector() {
    List({
      scroller: this.scroller,
      initialIndex: this.selectorProtocols.length - 1
    }) {
      ForEach(this.selectorProtocols, (value: Protocol) => {
        ListItem() {
          Column() {
            Text(value.toString().toUpperCase())
              .fontColor(value === this.newSelected ? protocolColor(value) : $r("sys.color.font_primary"))
          }
          .padding(12)
          .width(this.comp_width)
          .alignItems(HorizontalAlign.Center)
          .backgroundColor(value === this.newSelected ? protocolBGColor(value) : $r("sys.color.background_primary"))
        }
      })
    }
    .listDirection(Axis.Horizontal)
    .width(this.scrollWidth)
    .height(this.comp_height + 12)
    .scrollBar(BarState.Off)
    .enableScrollInteraction(false)
  }

  build() {
    Column() {
      // 交互区域：负责高度同步
      Column() {
        Text(this.selected.toString().toUpperCase())
      }
      .width(this.comp_width)
      .padding({ top: 12 })
      .alignItems(HorizontalAlign.Center)
      .onAreaChange((_, b) => {
        this.comp_height = b.height.valueOf() as number
      })

      // 提示文字：不参与高度同步
      Text("按住滑动")
        .fontSize(10)
        .fontColor($r("sys.color.font_secondary"))
        .opacity(0.6)
        .margin({ top: 2 })
    }
    .padding({ bottom: 10 })
    .borderRadius(12)
    .onTouch((event) => {
      if (event.type === TouchType.Down) {
        this.isSelecting = true
      } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
        this.isSelecting = false
        this.clearMoveTimer()
      }
    })
    .gesture(
      PanGesture({ fingers: 1 })
        .onActionStart(() => {
          this.isSelecting = true
          this.newSelected = this.selected
        })
        .onActionUpdate((event: GestureEvent) => {
          const x = event.fingerList[0].localX
          const currentOffset = this.scroller.currentOffset()?.xOffset ?? 0

          const listLeftRelativeToComponent = this.comp_width - this.scrollWidth
          const effectiveX = x - listLeftRelativeToComponent

          if (x >= listLeftRelativeToComponent && x <= this.comp_width) {
            const index = Math.floor((effectiveX + currentOffset) / this.comp_width)
            if (index >= 0 && index < this.selectorProtocols.length) {
              this.newSelected = this.selectorProtocols[index]
            }
          }

          if (x > this.comp_width) {
            if (this.scrollerMoveTimer === 0) {
              let move = () => {
                let newIndex = this.selectorProtocols.indexOf(this.newSelected) + 1
                if (newIndex <= this.selectorProtocols.length - 1) {
                  this.scroller.scrollToIndex(newIndex, true, ScrollAlign.END)
                  this.newSelected = this.selectorProtocols[newIndex]
                } else {
                  this.clearMoveTimer()
                }
              }
              move()
              this.scrollerMoveTimer = setInterval(move, 300)
            }
          } else if (x < listLeftRelativeToComponent) {
            if (this.scrollerMoveTimer === 0) {
              let move = () => {
                let newIndex = this.selectorProtocols.indexOf(this.newSelected) - 1
                if (newIndex >= 0) {
                  this.scroller.scrollToIndex(newIndex, true, ScrollAlign.START)
                  this.newSelected = this.selectorProtocols[newIndex]
                } else {
                  this.clearMoveTimer()
                }
              }
              move()
              this.scrollerMoveTimer = setInterval(move, 300)
            }
          } else {
            this.clearMoveTimer()
          }
        })
        .onActionEnd(() => {
          this.isSelecting = false
          this.onChange(this.newSelected)
          this.clearMoveTimer()
        })
        .onActionCancel(() => {
          this.isSelecting = false
          this.clearMoveTimer()
        })
    )
    .bindPopup(this.isSelecting, {
      builder: this.selector(),
      placement: Placement.TopRight,
      autoCancel: false,
      enableArrow: false,
      radius: 12,
      popupColor: $r("sys.color.background_primary")
    })
    .hitTestBehavior(HitTestMode.Block)
  }
}
