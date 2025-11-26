import { vibrator } from "@kit.SensorServiceKit"
import { AppManager } from "../../AppManager"
import { CompSize, Position } from "../../LayoutUtil"
import { lane } from "../../util/Conversion"
import { EventHelper } from "../../util/EventHelper"
import { UIType, WindowUtil } from "../../WindowUtil"
import { MyFrameCallback } from "../HMRouterIndex"

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
    let sequenceData = ""
    AppManager.layout.comp_sequence.forEach((value) => {
      let size = AppManager.layout.getCompSize(value)
      AppManager.layout.MaxHeight = Math.max(AppManager.layout.MaxHeight, size.grid_y+size.lane_h)
      sequenceData += `${value}_${size.grid_x}_${size.grid_y}_${size.lane_w}_${size.lane_h}|`
    })
    AppManager.preference.updateSequence(sequenceData.length>0?sequenceData.substring(0,sequenceData.length-1):sequenceData)
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
    .alignItems((!this.isHorizontal)?(this.addDirection == PanDirection.Up?VerticalAlign.Top:VerticalAlign.Bottom):VerticalAlign.Center)
    .justifyContent(this.isHorizontal?(this.addDirection == PanDirection.Left?FlexAlign.Start:FlexAlign.End):FlexAlign.Center)
    .width((!this.isHorizontal)?this.length-56:28)
    .height(this.isHorizontal?this.length-56:28)
    .offset({
      x: this.addDirection == PanDirection.Right?-10:0,
      y: this.addDirection == PanDirection.Down?-10:0
    })
    .gesture(PanGesture({ direction: this.isHorizontal?PanDirection.Horizontal:PanDirection.Vertical, fingers: 1 })
      .onActionStart(() => {
        EventHelper.emitterPublish("resize_start")
      })
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
    .hitTestBehavior(HitTestMode.Block)
  }
}

@ComponentV2
export struct ResizableComponent {
  @Param @Require comp_type: string
  @Local comp_size: CompSize = AppManager.layout.getCompSize(this.comp_type)
  @BuilderParam content: ()=>void
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
  @Computed
  get grid_size() {
    return lane(1)
  }
  @Computed
  get tempPosOffsetX(): number {
    if (!this.comp_size.isDragging && this.comp_size.find_next_grid) {
      return (this.comp_size.next_grid_x - this.comp_size.grid_x)*(this.grid_size+10)
    }else {
      return 0
    }
  }
  @Computed
  get tempPosOffsetY() {
    if (!this.comp_size.isDragging && this.comp_size.find_next_grid) {
      return (this.comp_size.next_grid_y - this.comp_size.grid_y)*(this.grid_size+10)
    }else {
      return 0
    }
  }

  aboutToAppear(): void {
    EventHelper.emitterListener("resize_off", () => {
      animateToImmediately(layoutAnimationParm, () => {
        this.comp_size.isResize = false
        this.comp_size.isOnOverlay = false
        this.comp_size.isDragging = false
      })
    })
    EventHelper.emitterListener("drag_overlay_cancel", () => {
      animateToImmediately(layoutAnimationParm, () => {
        this.comp_size.isResize = false
        this.comp_size.isDragging = false
        this.comp_size.find_next_grid = false
      })
    })
  }

  build() {
    Stack({alignContent: Alignment.Center}) {
      if (this.comp_size.find_next_grid && this.comp_size.isDragging) {
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
      Stack() {
        Column() {
          this.content()
        }
        .alignItems(HorizontalAlign.Center)
        .justifyContent(FlexAlign.Center)
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
        .width(lane(this.comp_size.lane_w) + this.offset_w)
        .height(lane(this.comp_size.lane_h) + this.offset_h)
        .gesture(GestureGroup(GestureMode.Parallel,LongPressGesture({ repeat: false, fingers: 1, duration: 500 })
          .onAction(() => {
            vibrator.startVibration({
              type: 'time',
              duration: 1,
            }, {
              id: 0,
              usage: 'touch'
            }, () => {})
          }),
          PanGesture({direction: PanDirection.All, fingers: 1})
            .onActionStart(() => {
              this.comp_size.find_next_grid = true
              this.pan_offset_x = 0
              this.pan_offset_y = 0
              this.comp_size.next_grid_x = this.comp_size.grid_x
              this.comp_size.next_grid_y = this.comp_size.grid_y
              this.comp_size.floatingX = this.comp_size.grid_x
              this.comp_size.floatingY = this.comp_size.grid_y
            })
            .onActionUpdate((event) => {
              if (Math.abs(event.offsetY - this.pan_offset_y) <= 30) {
                this.pan_offset_x = event.offsetX
                this.pan_offset_y = event.offsetY
              }
              this.comp_size.floatingX = this.comp_size.grid_x * this.grid_size + (this.comp_size.grid_x-1)*10 + this.pan_offset_x
              this.comp_size.floatingY = this.comp_size.grid_y * this.grid_size + (this.comp_size.grid_y-1)*10 + this.pan_offset_y
              let floatPos = AppManager.layout.updateGridPosition({
                x: this.comp_size.floatingX,
                y: this.comp_size.floatingY,
              }, this.comp_size.lane_w, this.comp_size.lane_h)
              // 位置合法
              if (floatPos.x >= 0 && !AppManager.layout.isOutOfBounds(floatPos.x, floatPos.y, this.comp_size.lane_w, this.comp_size.lane_h)) {
                if (this.comp_size.next_grid_x != floatPos.x || this.comp_size.next_grid_y != floatPos.y) {
                  this.comp_size.next_grid_x = floatPos.x
                  this.comp_size.next_grid_y = floatPos.y
                  this.comp_size.find_next_grid = true
                  AppManager.layout.pushObstacle(this.comp_type, {
                    x: this.comp_size.next_grid_x,
                    y: this.comp_size.next_grid_y,
                  }, this.comp_size.lane_w, this.comp_size.lane_h)
                }
              }else {
                AppManager.layout.cancelTempPos()
              }
            })
            .onActionEnd(() => {
              let old_grid: Position = {x:this.comp_size.grid_x, y: this.comp_size.grid_y}
              AppManager.layout.confirmTempPos()
              this.getUIContext()?.postFrameCallback(new MyFrameCallback(() => {
                this.pan_offset_x -= (this.comp_size.grid_x - old_grid.x)*(this.grid_size+10)
                this.pan_offset_y -= (this.comp_size.grid_y - old_grid.y)*(this.grid_size+10)
                animateToImmediately(layoutAnimationParm, () => {
                  this.pan_offset_x = 0
                  this.pan_offset_y = 0
                  this.comp_size.isResize = true
                })
                setTimeout(() => {
                  this.comp_size.isDragging = false
                }, 1)
              }));
              EventHelper.emitterPublish("drag_overlay_off")
              setTimeout(() => {
                AppManager.layout.updateSequence()
              },10)
            }))
        )
        .onGestureJudgeBegin((gestureInfo: GestureInfo) => {
          if (gestureInfo.type == GestureControl.GestureType.LONG_PRESS_GESTURE) {
            if (!this.comp_size.isResize) {
              this.comp_size.isResize = true
              EventHelper.emitterPublish("drag_overlay_on", {
                data: {
                  type: this.comp_type
                }
              })
            }
            if (this.comp_size.isResize) {
              return GestureJudgeResult.CONTINUE;
            }else {
              return GestureJudgeResult.REJECT;
            }
          }
          if (gestureInfo.type == GestureControl.GestureType.PAN_GESTURE) {
            if (this.comp_size.isResize) {
              if (!this.comp_size.isOnOverlay) {
                EventHelper.emitterPublish("drag_overlay_only_drag", {
                  data: {
                    type: this.comp_type
                  }
                })
              }else {
                EventHelper.emitterPublish("drag_overlay_move")
              }
              animateToImmediately(layoutAnimationParm, () => {
                this.comp_size.isResize = false
              })
              this.comp_size.isDragging = true
            }
            if (this.comp_size.isDragging) {
              return GestureJudgeResult.CONTINUE;
            }else {
              return GestureJudgeResult.REJECT;
            }
          }
          return GestureJudgeResult.CONTINUE;
        })
        if (this.comp_size.isResize) {
          Stack({alignContent: Alignment.Center}) {
            ResizeBall({
              addDirection: PanDirection.Left,
              extra: this.comp_size.offset_l!!,
              isAddable: ()=>{return this.comp_size.grid_x > 0
                && AppManager.layout.getObstacles(this.comp_type, {x:this.comp_size.grid_x-1,y:this.comp_size.grid_y}, this.comp_size.lane_w+1, this.comp_size.lane_h).length === 0},
              isDeletable: ()=>{return this.comp_size.lane_w > 1},
              isResize: this.comp_size.isResize,
              lane: this.comp_size.lane_w!!,
              length: lane(this.comp_size.lane_h) + this.offset_h,
              pos: this.comp_size.grid_x!!
            })
              .position({
                x: -8,
                y: 28
              })
            ResizeBall({
              addDirection: PanDirection.Up,
              extra: this.comp_size.offset_u!!,
              isAddable: ()=>{return this.comp_size.grid_y > 0
                && AppManager.layout.getObstacles(this.comp_type, {x:this.comp_size.grid_x,y:this.comp_size.grid_y-1}, this.comp_size.lane_w, this.comp_size.lane_h+1).length === 0},
              isDeletable: ()=>{return this.comp_size.lane_h > 1},
              isResize: this.comp_size.isResize,
              lane: this.comp_size.lane_h!!,
              length: lane(this.comp_size.lane_w) + this.offset_w,
              pos: this.comp_size.grid_y!!
            })
              .position({
                x: 28,
                y: -8
              })
            ResizeBall({
              addDirection: PanDirection.Down,
              extra: this.comp_size.offset_d!!,
              isAddable: ()=>{return this.comp_size.grid_y + this.comp_size.lane_h < AppManager.layout.LayoutHeight()
                && AppManager.layout.getObstacles(this.comp_type, {x:this.comp_size.grid_x,y:this.comp_size.grid_y}, this.comp_size.lane_w, this.comp_size.lane_h+1).length === 0},
              isDeletable: ()=>{return this.comp_size.lane_h > 1},
              isResize: this.comp_size.isResize,
              lane: this.comp_size.lane_h!!,
              length: lane(this.comp_size.lane_w) + this.offset_w
            })
              .position({
                x: 28,
                y: lane(this.comp_size.lane_h) + this.comp_size.offset_d + this.comp_size.offset_u -10
              })
            ResizeBall({
              addDirection: PanDirection.Right,
              extra: this.comp_size.offset_r!!,
              isAddable: ()=>{return this.comp_size.grid_x + this.comp_size.lane_w < AppManager.layout.LayoutWidth()
                && AppManager.layout.getObstacles(this.comp_type, {x:this.comp_size.grid_x,y:this.comp_size.grid_y}, this.comp_size.lane_w+1, this.comp_size.lane_h).length === 0},
              isDeletable: ()=>{return this.comp_size.lane_w > 1},
              isResize: this.comp_size.isResize,
              lane: this.comp_size.lane_w!!,
              length: lane(this.comp_size.lane_h) + this.offset_h
            })
              .position({
                x: lane(this.comp_size.lane_w) + this.comp_size.offset_r + this.comp_size.offset_l -10,
                y: 28
              })
          }
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
          .width(lane(this.comp_size.lane_w) + this.offset_w)
          .height(lane(this.comp_size.lane_h) + this.offset_h)
          .borderWidth(this.comp_size.isResize?2:0)
          .borderColor($r("sys.color.brand"))
          .borderRadius(18)
          .hitTestBehavior(HitTestMode.Transparent)
        }
      }
      .position({
        x: -this.comp_size.offset_l + (this.comp_size.isDragging ? this.pan_offset_x : 0) + this.tempPosOffsetX,
        y: -this.comp_size.offset_u + (this.comp_size.isDragging ? this.pan_offset_y : 0) + this.tempPosOffsetY
      })
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      .width(lane(this.comp_size.lane_w) + this.offset_w)
      .height(lane(this.comp_size.lane_h) + this.offset_h)
      .borderRadius(18)
      .backgroundColor($r("sys.color.comp_background_primary"))
    }
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .backgroundColor(Color.Transparent)
    .width(lane(this.comp_size.lane_w))
    .height(lane(this.comp_size.lane_h))
    .clip(false)
    .id(this.comp_type)
    .onTouch((event) => {
      event.stopPropagation()
      if (event.type == TouchType.Down) {
        if (!this.comp_size.isResize) {
          EventHelper.emitterPublish("resize_off")
        }
      }
    })
  }
}