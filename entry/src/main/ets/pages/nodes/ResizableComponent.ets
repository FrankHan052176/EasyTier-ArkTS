import { vibrator } from "@kit.SensorServiceKit"
import { CompSize, LayoutUtil } from "../../LayoutUtil"
import { lane } from "../../util/Conversion"
import { EventHelper } from "../../util/EventHelper"
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
  @Local fingerOffset: number = 0
  @Local disable_a: boolean = false
  @Local disable_d: boolean = false
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
        case UIType.Column_1: {
          return Math.min(2, this.lane+1)
        }
        case UIType.Column_2: {
          return Math.min(4, this.lane+1)
        }
        case UIType.Column_3: {
          return Math.min(6, this.lane+1)
        }
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
  @Local timer: number = -1
  @Local pan_offset_x: number = 0
  @Local pan_offset_y: number = 0

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
      this.content()
      if (this.isResize) {
        ResizeBall({
          addDirection: PanDirection.Left,
          extra: this.comp_size.offset_l!!,
          isAddable: ()=>{return false},
          isDeletable: ()=>{return true},
          isResize: this.isResize,
          lane: this.comp_size.lane_h!!,
          length: lane(this.comp_size.lane_h) + this.offset_h
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
          length: lane(this.comp_size.lane_w) + this.offset_w
        })
          .position({
            x: 18,
            y: -8
          })
        ResizeBall({
          addDirection: PanDirection.Down,
          extra: this.comp_size.offset_d!!,
          isAddable: ()=>{return true},
          isDeletable: ()=>{return true},
          isResize: this.isResize,
          lane: this.comp_size.lane_h!!,
          length: lane(this.comp_size.lane_w) + this.offset_w
        })
          .position({
            x: 18,
            y: lane(this.comp_size.lane_h) + this.comp_size.offset_d + this.comp_size.offset_u -10
          })
        ResizeBall({
          addDirection: PanDirection.Right,
          extra: this.comp_size.offset_r!!,
          isAddable: ()=>{return true},
          isDeletable: ()=>{return true},
          isResize: this.isResize,
          lane: this.comp_size.lane_w!!,
          length: lane(this.comp_size.lane_h) + this.offset_h
        })
          .position({
            x: lane(this.comp_size.lane_w) + this.comp_size.offset_r + this.comp_size.offset_l -10,
            y: 18
          })
      }
    }
    .gesture(GestureGroup(GestureMode.Sequence,LongPressGesture({ repeat: false, fingers: 1 })
      .onAction((event: GestureEvent|undefined) => {
        if(event && !this.isResize) {
          vibrator.startVibration({
            type: 'time',
            duration: 1,
          }, {
            id: 0,
            usage: 'touch'
          }, () => {})
          animateToImmediately(animationParm, () => {
            this.isResize = true
          })
        }
      }),
      PanGesture({direction: PanDirection.All, fingers: 1})
        .onActionStart((event) => {
          if(event) {
            animateToImmediately(animationParm, () => {
              this.isResize = false
            })
          }
        }).onActionUpdate((event) => {
        if(event) {
          this.pan_offset_x = event.offsetX
          this.pan_offset_y = event.offsetY
        }
      }).onActionEnd((event) => {
        if (event) {
          animateToImmediately(animationParm, () => {
            this.isResize = true
            this.pan_offset_x = 0
            this.pan_offset_y = 0
          })
        }
      }))
    )
    .borderWidth(this.isResize?2:0)
    .borderColor($r("sys.color.brand"))
    .borderRadius(18)
    .width(lane(this.comp_size.lane_w) + this.offset_w)
    .height(lane(this.comp_size.lane_h) + this.offset_h)
    .position({
      x: -this.comp_size.offset_l + this.pan_offset_x,
      y: -this.comp_size.offset_u + this.pan_offset_y
    })
    .clickEffect({
      level: ClickEffectLevel.LIGHT
    })
  }
}