import { vibrator } from "@kit.SensorServiceKit"
import { CompSize, LayoutUtil } from "../../LayoutUtil"
import { lane } from "../../util/Conversion"
import { EventHelper } from "../../util/EventHelper"
import { Logger } from "../../util/Logger"
import { UIType, WindowUtil } from "../../WindowUtil"

export const layoutAnimationParm: AnimateParam = {
  duration: 200,
  curve: Curve.Friction
}

@ComponentV2
struct ResizeBall {
  @Param @Require addDirection: PanDirection
  @Param @Require isResize: boolean
  @Param @Require isAddable: () => boolean
  @Param @Require isDeletable: () => boolean
  @Param @Require lane: number
  @Param @Require length: number
  @Event $lane: (val: number) => void = (val: number) => {}
  @Param @Require extra: number
  @Event $extra: (val: number) => void = (val: number) => {}
  @Param pos: number = 0
  @Event $pos: (val: number) => void = (val: number) => {}
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
    if (this.isHorizontal) {
      return lane(need)
    }else {
      return lane(need)
    }
  }

  canExtra(offset: number): boolean {
    return offset>0?this.isAddable() && this.getNextLane() > this.lane:this.isDeletable() && this.getPreLane() < this.lane
  }

  extraLane(offset: number) {
    if (offset>0) {
      if (this.addDirection == PanDirection.Left || this.addDirection == PanDirection.Up) {
        this.$pos(this.pos-1)
      }
      this.$lane(this.getNextLane())
    }else {
      if (this.addDirection == PanDirection.Left || this.addDirection == PanDirection.Up) {
        this.$pos(this.pos+1)
      }
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
      }
    }else {
      return Math.min(10, this.lane+1)
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
        animateToImmediately(layoutAnimationParm, () => {
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
              this.fingerOffset = this.getRawOffset(event)
            }else if (this.canExtra(offset) && (offset-10 >= this.getLane(1)*0.6 || offset+10 <= this.getLane(1)*-0.5)) {
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
        animateToImmediately(layoutAnimationParm, () => {
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

  @Computed
  get offset_w() {
    return this.comp_size.offset_l + this.comp_size.offset_r
  }
  @Computed
  get offset_h() {
    return this.comp_size.offset_u + this.comp_size.offset_d
  }
  @Computed
  get grid_size() {
    return lane(1)
  }
  @Computed
  get tempPosOffsetX() {
    if (!this.comp_size.isFloating && this.comp_size.find_next_grid) {
      return (this.comp_size.next_grid_x - this.comp_size.grid_x)*(this.grid_size+10)
    }else {
      return 0
    }
  }
  @Computed
  get tempPosOffsetY() {
    if (!this.comp_size.isFloating && this.comp_size.find_next_grid) {
      return (this.comp_size.next_grid_y - this.comp_size.grid_y)*(this.grid_size+10)
    }else {
      return 0
    }
  }

  aboutToAppear(): void {
    EventHelper.emitterListener("resize_off", () => {
      animateToImmediately(layoutAnimationParm, () => {
        this.isResize = false
      })
    })
  }

  build() {
    Stack({alignContent: Alignment.Center}) {
      if (this.comp_size.find_next_grid && this.comp_size.isFloating) {
        Column()
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
          .width(lane(this.comp_size.lane_w))
          .height(lane(this.comp_size.lane_h))
          .backgroundColor($r("sys.color.font_on_fourth"))
          .borderWidth(2)
          .borderColor($r("sys.color.font_on_tertiary"))
          .borderRadius(18)
          .position({
            x: (this.comp_size.next_grid_x-this.comp_size.grid_x)*(lane(1)+10),
            y: (this.comp_size.next_grid_y-this.comp_size.grid_y)*(lane(1)+10)
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
              isAddable: ()=>{return this.comp_size.grid_x > 0
                && LayoutUtil.getObstacles(this.comp_type, {x:this.comp_size.grid_x-1,y:this.comp_size.grid_y}, this.comp_size.lane_w+1, this.comp_size.lane_h).length === 0},
              isDeletable: ()=>{return this.comp_size.lane_w > 1},
              isResize: this.isResize,
              lane: this.comp_size.lane_w!!,
              length: lane(this.comp_size.lane_h) + this.offset_h,
              pos: this.comp_size.grid_x!!
            })
              .position({
                x: -8,
                y: 18
              })
            ResizeBall({
              addDirection: PanDirection.Up,
              extra: this.comp_size.offset_u!!,
              isAddable: ()=>{return this.comp_size.grid_y > 0
                && LayoutUtil.getObstacles(this.comp_type, {x:this.comp_size.grid_x,y:this.comp_size.grid_y-1}, this.comp_size.lane_w, this.comp_size.lane_h+1).length === 0},
              isDeletable: ()=>{return this.comp_size.lane_h > 1},
              isResize: this.isResize,
              lane: this.comp_size.lane_h!!,
              length: lane(this.comp_size.lane_w) + this.offset_w,
              pos: this.comp_size.grid_y!!
            })
              .position({
                x: 18,
                y: -10
              })
            ResizeBall({
              addDirection: PanDirection.Down,
              extra: this.comp_size.offset_d!!,
              isAddable: ()=>{return this.comp_size.grid_y + this.comp_size.lane_h < LayoutUtil.LayoutHeight()
                && LayoutUtil.getObstacles(this.comp_type, {x:this.comp_size.grid_x,y:this.comp_size.grid_y}, this.comp_size.lane_w, this.comp_size.lane_h+1).length === 0},
              isDeletable: ()=>{return this.comp_size.lane_h > 1},
              isResize: this.isResize,
              lane: this.comp_size.lane_h!!,
              length: lane(this.comp_size.lane_w) + this.offset_w
            })
              .position({
                x: 18,
                y: lane(this.comp_size.lane_h) + this.comp_size.offset_d + this.comp_size.offset_u -12
              })
            ResizeBall({
              addDirection: PanDirection.Right,
              extra: this.comp_size.offset_r!!,
              isAddable: ()=>{return this.comp_size.grid_x + this.comp_size.lane_w < LayoutUtil.LayoutWidth()
                && LayoutUtil.getObstacles(this.comp_type, {x:this.comp_size.grid_x,y:this.comp_size.grid_y}, this.comp_size.lane_w+1, this.comp_size.lane_h).length === 0},
              isDeletable: ()=>{return this.comp_size.lane_w > 1},
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
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
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
              animateToImmediately(layoutAnimationParm, () => {
                this.isResize = true
                this.comp_scale = 1
              })
            }
          }),
          PanGesture({direction: PanDirection.All, fingers: 1})
            .onActionStart((event) => {
              this.comp_size.next_grid_x = this.comp_size.grid_x
              this.comp_size.next_grid_y = this.comp_size.grid_y
              animateToImmediately(layoutAnimationParm, () => {
                this.isResize = false
                this.comp_size.isFloating = true
                this.touch_x = event.fingerList[0].localX
                this.touch_y = event.fingerList[0].localY
              })
            })
            .onActionUpdate((event) => {
              this.pan_offset_x = event.offsetX
              this.pan_offset_y = event.offsetY
              let maxGridX = LayoutUtil.LayoutWidth() * this.grid_size + (LayoutUtil.LayoutWidth()-1)*10
              let maxGridY = LayoutUtil.LayoutHeight() * this.grid_size + (LayoutUtil.LayoutHeight()-1)*10
              this.comp_size.floatingX = this.comp_size.grid_x * this.grid_size + (this.comp_size.grid_x-1)*10 + this.pan_offset_x
              this.comp_size.floatingY = this.comp_size.grid_y * this.grid_size + (this.comp_size.grid_y-1)*10 + this.pan_offset_y
              // 越界
              if (this.comp_size.floatingX < 0 && this.comp_size.floatingX > maxGridX && this.comp_size.floatingY < 0 && this.comp_size.floatingY > maxGridY) {
                LayoutUtil.cancelTempPos()
              }else {
                let floatPos = LayoutUtil.updateGridPosition({
                  x: this.comp_size.floatingX,
                  y: this.comp_size.floatingY,
                }, this.comp_size.lane_w, this.comp_size.lane_h)
                // 位置合法
                if (floatPos.x >= 0) {
                  if (this.comp_size.next_grid_x != floatPos.x || this.comp_size.next_grid_y != floatPos.y || !this.comp_size.find_next_grid) {
                    this.comp_size.next_grid_x = floatPos.x
                    this.comp_size.next_grid_y = floatPos.y
                    this.comp_size.find_next_grid = true
                    LayoutUtil.pushObstacle(this.comp_type, {
                      x: this.comp_size.next_grid_x,
                      y: this.comp_size.next_grid_y,
                    }, this.comp_size.lane_w, this.comp_size.lane_h)
                  }
                }else {
                  // 位置非法
                  LayoutUtil.cancelTempPos()
                }
              }
            })
            .onActionEnd(() => {
              LayoutUtil.confirmTempPos()
              animateToImmediately(layoutAnimationParm, () => {
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
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      .width(lane(this.comp_size.lane_w) + this.offset_w)
      .height(lane(this.comp_size.lane_h) + this.offset_h)
      .borderWidth(this.isResize?2:0)
      .borderColor($r("sys.color.brand"))
      .borderRadius(18)
      .zIndex(this.comp_size.isFloating?999:1)
      .position({
        x: -this.comp_size.offset_l + (this.comp_size.isFloating ? this.pan_offset_x : 0) + this.tempPosOffsetX,
        y: -this.comp_size.offset_u + (this.comp_size.isFloating ? this.pan_offset_y : 0) + this.tempPosOffsetY
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
            animateToImmediately(layoutAnimationParm, () => {
              this.comp_scale = 0.9
            })
          }else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
            animateToImmediately(layoutAnimationParm, () => {
              this.comp_scale = 1
            })
          }
        }
      })
    }
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .width(lane(this.comp_size.lane_w))
    .height(lane(this.comp_size.lane_h))
    .clip(false)
    .id(this.comp_type)
  }
}