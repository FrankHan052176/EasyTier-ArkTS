import { vibrator } from "@kit.SensorServiceKit"
import { CompSize, LayoutUtil, Position } from "../../LayoutUtil"
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

  isValidResize(newLane: number): boolean {
    const compSize = LayoutUtil.getCompSize(this.compType);
    let newWidth = compSize.lane_w;
    let newHeight = compSize.lane_h;

    if (this.isHorizontal) {
      newWidth = newLane;
    } else {
      newHeight = newLane;
    }

    const result = LayoutUtil.isValidResize(compSize, newWidth, newHeight);
    if (result.isValid) {
      this.lastValidLane = newLane;
    } else {
      Logger.warn(`调整大小被拒绝: ${result.reason}`);
    }
    return result.isValid;
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
  @Local isDragging: boolean = false
  @BuilderParam content: ()=>void
  @Local timer: number = -1
  @Local pan_offset_x: number = 0
  @Local pan_offset_y: number = 0
  @Local drag_start_x: number = 0
  @Local drag_start_y: number = 0
  @Local original_x: number = 0
  @Local original_y: number = 0

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

  isValidDragPosition(newX: number, newY: number): boolean {
    const tempSize = new CompSize();
    tempSize.x = newX;
    tempSize.y = newY;
    tempSize.lane_w = this.comp_size.lane_w;
    tempSize.lane_h = this.comp_size.lane_h;

    // 检查边界
    if (LayoutUtil.isOutOfBounds(tempSize)) {
      return false;
    }

    // 检查重叠
    for (const compType of LayoutUtil.comp_sequence) {
      if (compType === this.comp_type) continue;
      const otherComp = LayoutUtil.getCompSize(compType);
      if (LayoutUtil.isOverlap(tempSize, otherComp)) {
        return false;
      }
    }

    return true;
  }

  findValidPosition(targetX: number, targetY: number): Position {
    // 尝试目标位置
    if (this.isValidDragPosition(targetX, targetY)) {
      return { x: targetX, y: targetY };
    }

    // 在周围寻找空位
    const searchRadius = 2;
    for (let dy = -searchRadius; dy <= searchRadius; dy++) {
      for (let dx = -searchRadius; dx <= searchRadius; dx++) {
        const testX = Math.max(0, Math.min(WindowUtil.uiType - this.comp_size.lane_w, targetX + dx));
        const testY = Math.max(0, Math.min(10 - this.comp_size.lane_h, targetY + dy));

        if (this.isValidDragPosition(testX, testY)) {
          return { x: testX, y: testY };
        }
      }
    }

    // 如果找不到，返回原位置
    return { x: this.original_x, y: this.original_y };
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
            y: -8
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
            y: lane(this.comp_size.lane_h) + this.comp_size.offset_d + this.comp_size.offset_u -10
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
            this.drag_start_x = event.offsetX
            this.drag_start_y = event.offsetY
            this.original_x = this.comp_size.x
            this.original_y = this.comp_size.y
            animateToImmediately(animationParm, () => {
              this.isResize = false
              this.isDragging = true
            })
          }
        })
        .onActionUpdate((event) => {
          if(event) {
            this.pan_offset_x = event.offsetX - this.drag_start_x
            this.pan_offset_y = event.offsetY - this.drag_start_y
          }
        })
        .onActionEnd((event) => {
          if (event) {const gridSize = lane(1)
            const gridMovementX = Math.round(this.pan_offset_x / gridSize)
            const gridMovementY = Math.round(this.pan_offset_y / gridSize)

            const targetX = this.original_x + gridMovementX
            const targetY = this.original_y + gridMovementY

            // 寻找合法位置并处理重叠
            const validPos = this.findValidPosition(targetX, targetY)
            this.comp_size.x = validPos.x
            this.comp_size.y = validPos.y

            // 推动可能重叠的组件
            LayoutUtil.pushOverlappingComponents(this.comp_size, this.comp_type)
            animateToImmediately(animationParm, () => {
              this.isResize = true
              this.isDragging = false
              this.pan_offset_x = 0
              this.pan_offset_y = 0
            })
          }
        })
    ))
    .borderWidth(this.isResize?2:0)
    .borderColor($r("sys.color.brand"))
    .borderRadius(18)
    .width(lane(this.comp_size.lane_w) + this.offset_w)
    .height(lane(this.comp_size.lane_h) + this.offset_h)
    .position({
      x: -this.comp_size.offset_l + (this.isDragging ? this.pan_offset_x : 0),
      y: -this.comp_size.offset_u + (this.isDragging ? this.pan_offset_y : 0)
    })
    .clickEffect({
      level: ClickEffectLevel.LIGHT
    })
  }
}