import { vibrator } from "@kit.SensorServiceKit"
import { CompSize, LayoutUtil } from "../../LayoutUtil"
import { lane } from "../../util/Conversion"
import { EventHelper } from "../../util/EventHelper"
import { Logger } from "../../util/Logger"
import { UIType, WindowUtil } from "../../WindowUtil"

const animationParm: AnimateParam = {
  duration: 200,
  curve: Curve.Friction
}

@ComponentV2
struct ResizeBall {
  @Param @Require addDirection: PanDirection
  @Param @Require isResize: boolean
  @Param @Require isAddable: () => boolean
  @Param @Require isDeletable: () => boolean
  @Param @Require length: number
  @Param @Require lane: number
  @Event $lane: (val: number) => void = (val: number) => {}
  @Param @Require extra: number
  @Event $extra: (val: number) => void = (val: number) => {}
  @Param @Require compType: string
  @Local fingerOffset: number = 0
  @Local disable_a: boolean = false
  @Local disable_d: boolean = false
  @Local lastValidLane: number = 1
  @BuilderParam content: ()=>void

  @Computed
  get isHorizontal() {
    return this.addDirection == PanDirection.Left || this.addDirection == PanDirection.Right
  }

  getFixScale(): number {
    return (this.addDirection == PanDirection.Left || this.addDirection == PanDirection.Up)?-1:1
  }

  getOffset(event: GestureEvent): number {
    if (this.isHorizontal) {
      return (event.offsetX - this.fingerOffset)*this.getFixScale()
    }else {
      return (event.offsetY - this.fingerOffset)*this.getFixScale()
    }
  }

  getRawOffset(event: GestureEvent): number {
    return this.isHorizontal?event.offsetX:event.offsetY
  }

  getLane(need: number = this.lane): number {
    return lane(need)
  }

  canExtra(offset: number): boolean {
    return offset>0?this.isAddable() && this.getNextLane() > this.lane:this.isDeletable() && this.getPreLane() < this.lane
  }

  extraLane(offset: number) {
    if (offset>0) {
      this.$lane(this.getNextLane())
    }else {
      this.$lane(this.getPreLane())
    }
  }

  getNextLane(): number {
    if (this.isHorizontal) {
      switch (WindowUtil.uiType) {
        case UIType.Column_1: return Math.min(2, this.lane+1)
        case UIType.Column_2: return Math.min(4, this.lane+1)
        case UIType.Column_3: return Math.min(6, this.lane+1)
        default: {
          return 0
        }
      }
    }else {
      return Math.min(4, this.lane+1)
    }
  }

  getPreLane(): number {
    return Math.max(1, this.lane-1)
  }

  build() {
    Row() {
      Stack() {
        Circle({ width: 18, height: 18 })
          .fill("#3A0a59f7")
        Circle({ width: 8, height: 8 })
          .fill($r("sys.color.brand"))
      }
    }
    .alignItems(VerticalAlign.Center)
    .justifyContent(FlexAlign.Center)
    .width(!this.isHorizontal?this.length-36:18)
    .height(this.isHorizontal?this.length-36:18)
    .gesture(PanGesture({ direction: this.isHorizontal?PanDirection.Horizontal:PanDirection.Vertical, fingers: 1 })
      .onActionUpdate((event) => {
        animateToImmediately(animationParm, () => {
          let offset = this.getOffset(event)
          if ((!this.disable_a && offset >= 0) || (!this.disable_d && offset < 0)) {
            this.disable_a = false
            this.disable_d = false
            if (Math.abs(offset) >= 30 && !this.canExtra(offset)) {
              this.$extra(0)
              if (offset < 0) {
                this.disable_d = true
              }else {
                this.disable_a = true
              }
            }else if (this.canExtra(offset) && (offset-10 >= this.getLane(1)*0.7 || offset+10 <= this.getLane(1)*-0.5)) {
              this.fingerOffset = this.getRawOffset(event)
              this.extraLane(offset)
            }else {
              this.$extra(offset)
            }
          }else {
            this.fingerOffset = this.getRawOffset(event)
          }
        })
      })
      .onActionEnd(() => {
        animateToImmediately(animationParm, () => {
          this.$extra(0)
          this.fingerOffset = 0
          this.disable_a = false
          this.disable_d = false
        })
      }))
    .hitTestBehavior(this.isResize ? HitTestMode.Block : HitTestMode.Default)
  }
}

@ComponentV2
export struct ResizableComponent {
  @Param @Require comp_type: string
  @Local comp_size: CompSize = LayoutUtil.getCompSize(this.comp_type)
  @Local isResize: boolean = false
  @BuilderParam content: ()=>void
  @Local comp_scale: number = 1
  @Local pan_offset_x: number = 0
  @Local pan_offset_y: number = 0
  @Local touch_x: number = 0
  @Local touch_y: number = 0
  @Local find_next_grid: boolean = false
  @Local next_grid_x: number = this.comp_size.grid_x
  @Local next_grid_y: number = this.comp_size.grid_y


  @Computed
  get offset_w() {
    return this.comp_size.offset_l + this.comp_size.offset_r
  }
  @Computed
  get offset_h() {
    return this.comp_size.offset_u + this.comp_size.offset_d
  }

  aboutToAppear(): void {
    EventHelper.emitterListener("resize_off", () => {
      animateToImmediately(animationParm, () => {
        this.isResize = false
      })
    })
  }

  build() {
    Stack({alignContent: Alignment.Center}) {
      if (this.find_next_grid) {
        Column()
          .width(lane(this.comp_size.lane_w))
          .height(lane(this.comp_size.lane_h))
          .backgroundColor($r("sys.color.font_on_fourth"))
          .borderWidth(2)
          .borderColor($r("sys.color.font_on_tertiary"))
          .borderRadius(18)
          .position({
            x: (this.next_grid_x-this.comp_size.grid_x)*(lane(1)+10),
            y: (this.next_grid_y-this.comp_size.grid_y)*(lane(1)+10)
          })
          .transition(TransitionEffect.asymmetric(
            TransitionEffect.OPACITY.animation({ duration: 200, curve: Curve.Ease }),
            TransitionEffect.OPACITY.animation({ duration: 1, curve: Curve.Ease })))
      }
      Column() {
        Stack({alignContent: Alignment.Center}) {
          this.content()
          if (this.isResize) {
            ResizeBall({
              addDirection: PanDirection.Left,
              extra: this.comp_size.offset_l!!,
              isAddable: ()=>{return false},
              isDeletable: ()=>{return true},
              isResize: this.isResize,
              lane: this.comp_size.lane_h!!,
              length: lane(this.comp_size.lane_h) + this.offset_h,
              compType: this.comp_type
            })
              .position({
                x: -8,
                y: 18
              })
            ResizeBall({
              addDirection: PanDirection.Up,
              extra: this.comp_size.offset_u!!,
              isAddable: ()=>{return false},
              isDeletable: ()=>{return true},
              isResize: this.isResize,
              lane: this.comp_size.lane_h!!,
              length: lane(this.comp_size.lane_w) + this.offset_w,
              compType: this.comp_type
            })
              .position({
                x: 18,
                y: -10
              })
            ResizeBall({
              addDirection: PanDirection.Down,
              extra: this.comp_size.offset_d!!,
              isAddable: ()=>{return true},
              isDeletable: ()=>{return true},
              isResize: this.isResize,
              lane: this.comp_size.lane_h!!,
              length: lane(this.comp_size.lane_w) + this.offset_w,
              compType: this.comp_type
            })
              .position({
                x: 18,
                y: lane(this.comp_size.lane_h) + this.comp_size.offset_d + this.comp_size.offset_u -12
              })
            ResizeBall({
              addDirection: PanDirection.Right,
              extra: this.comp_size.offset_r!!,
              isAddable: ()=>{return true},
              isDeletable: ()=>{return true},
              isResize: this.isResize,
              lane: this.comp_size.lane_w!!,
              length: lane(this.comp_size.lane_h) + this.offset_h,
              compType: this.comp_type
            })
              .position({
                x: lane(this.comp_size.lane_w) + this.comp_size.offset_r + this.comp_size.offset_l -10,
                y: 18
              })
          }
        }
        .gesture(GestureGroup(GestureMode.Sequence,LongPressGesture({ repeat: false, fingers: 1, duration: 300 })
          .onAction(() => {
            if(!this.isResize) {
              vibrator.startVibration({
                type: 'time',
                duration: 1,
              }, {
                id: 0,
                usage: 'touch'
              }, () => {})
              animateToImmediately(animationParm, () => {
                this.isResize = true
                this.comp_scale = 1
              })
            }
          }),
          PanGesture({direction: PanDirection.All, fingers: 1})
            .onActionStart((event) => {
              animateToImmediately(animationParm, () => {
                this.isResize = false
                this.comp_size.isFloating = true
                this.touch_x = event.fingerList[0].localX
                this.touch_y = event.fingerList[0].localY
                this.next_grid_x = this.comp_size.grid_x
                this.next_grid_y = this.comp_size.grid_y
              })
            })
            .onActionUpdate((event) => {
              this.pan_offset_x = event.offsetX
              this.pan_offset_y = event.offsetY
              this.comp_size.floatingX = this.comp_size.grid_x + this.pan_offset_x
              this.comp_size.floatingY = this.comp_size.grid_y + this.pan_offset_y
              let floatPos = LayoutUtil.updateGridPosition({
                x: this.comp_size.floatingX,
                y: this.comp_size.floatingY,
              }, this.comp_size.lane_w, this.comp_size.lane_h)
              if (floatPos.x >= 0) {
                this.next_grid_x = floatPos.x
                this.next_grid_y = floatPos.y
                this.find_next_grid = true
              }else {
                this.find_next_grid = false
              }
            })
            .onActionEnd(() => {
              this.find_next_grid = false
              animateToImmediately(animationParm, () => {
                this.comp_size.isFloating = false
                this.isResize = true
                this.pan_offset_x = 0
                this.pan_offset_y = 0
                this.comp_size.floatingX = this.comp_size.grid_x
                this.comp_size.floatingY = this.comp_size.grid_y
              })
            })
        ))
        .width(lane(this.comp_size.lane_w) + this.offset_w)
        .height(lane(this.comp_size.lane_h) + this.offset_h)
      }
      .width(lane(this.comp_size.lane_w) + this.offset_w)
      .height(lane(this.comp_size.lane_h) + this.offset_h)
      .borderWidth(this.isResize?2:0)
      .borderColor($r("sys.color.brand"))
      .borderRadius(18)
      .zIndex(this.comp_size.isFloating?999:1)
      .position({
        x: -this.comp_size.offset_l + (this.comp_size.isFloating ? this.pan_offset_x : 0),
        y: -this.comp_size.offset_u + (this.comp_size.isFloating ? this.pan_offset_y : 0)
      })
      .scale({
        centerX: "50%",
        centerY: "50%",
        x: this.comp_scale,
        y: this.comp_scale
      })
      .onTouch((event) => {
        if (!this.isResize && !this.comp_size.isFloating) {
          if (event.type === TouchType.Down) {
            animateToImmediately(animationParm, () => {
              this.comp_scale = 0.9
            })
          }else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
            animateToImmediately(animationParm, () => {
              this.comp_scale = 1
            })
          }
        }
      })
    }
    .width(lane(this.comp_size.lane_w))
    .height(lane(this.comp_size.lane_h))
    .clip(false)
  }
}