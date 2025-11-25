import { AppManager } from "./AppManager"
import { MyFrameCallback } from "./pages/HMRouterIndex"
import { layoutAnimationParm } from "./pages/nodes/ResizableComponent"
import { lane, preciseIntegerDivision } from "./util/Conversion"
import { Logger } from "./util/Logger"
import { WindowUtil } from "./WindowUtil"

@ObservedV2
export class CompSize {
  @Trace type: string = ""
  @Trace lane_w: number = 1
  @Trace lane_h: number = 1
  @Trace offset_l: number = 0
  @Trace offset_r: number = 0
  @Trace offset_u: number = 0
  @Trace offset_d: number = 0
  @Trace grid_x: number = 0
  @Trace grid_y: number = 0
  @Trace isResize: boolean = false
  @Trace isOnOverlay: boolean = false
  @Trace isDragging: boolean = false
  @Trace floatingX: number = 0
  @Trace floatingY: number = 0
  @Trace next_grid_x: number = 0
  @Trace next_grid_y: number = 0
  @Trace find_next_grid: boolean = false

  setPos(x: number, y: number): CompSize {
    this.grid_x = x;
    this.grid_y = y;
    return this
  }

  withType(type: string): CompSize {
    this.type = type
    return this
  }

  setSize(width: number, height: number): CompSize {
    this.lane_w = width
    this.lane_h = height
    return this
  }
}

export interface Position { x: number, y: number}
export interface CompSizeWithPos { type: string, x: number, y: number, width: number, height: number }

@ObservedV2
export class LayoutUtil {
  @Trace desktopPosX: number = 0;
  @Trace desktopPosY: number = 0;
  @Trace comp_types: string[] = ["Instances", "Logs", "Last", "SharedPeers", "QQ"]
  @Trace comp_sequence: string[] = []
  @Trace compSizeMap: Map<string, CompSize> = new Map
  @Trace InstancesSize: CompSize = new CompSize().withType("Instances")
  @Trace LastSize: CompSize = new CompSize().setPos(1,0).withType("Last")
  @Trace LogsSize: CompSize = new CompSize().setPos(0,1).withType("Logs")
  @Trace QQGSize: CompSize = new CompSize().setPos(1,2).withType("QQ")
  @Trace SharedPeersSize: CompSize = new CompSize().setPos(1,1).withType("SharedPeers")
  @Trace MaxHeight: number = 0
  @Trace MaxWidth: number = 0

  public static readonly MIN_COMP_WIDTH = 1;
  public static readonly MIN_COMP_HEIGHT = 1;

  initSequence(sequence: string) {
    sequence.split("|").forEach((data) => {
      let raw = data.split("_")
      let size:CompSizeWithPos = {
        type: raw[0],
        x: Number.parseInt(raw[1]),
        y: Number.parseInt(raw[2]),
        width: Number.parseInt(raw[3]),
        height: Number.parseInt(raw[4])
      }
      if (this.comp_types.indexOf(size.type) >= 0) {
        this.comp_sequence.push(size.type)
        let pos: Position = { x: size.x, y: size.y }
        if (this.getObstacles(size.type, { x: size.x, y: size.y }, size.width, size.height).length > 0 || this.isOutOfBounds(size.x, size.y, size.width, size.height)) {
          pos = this.findFreeSpace(size.width, size.height)
        }
        this.compSizeMap.set(size.type, new CompSize().setPos(pos.x, pos.y).setSize(size.width, size.height).withType(size.type))
        this.MaxHeight = Math.max(this.MaxHeight, pos.y+size.height)
        this.MaxWidth = Math.max(this.MaxWidth, pos.x+size.width)
      }
    })
  }

  updateNewUIType() {
    let width = WindowUtil.uiType
    if (this.MaxWidth > width || this.MaxWidth < width - 1) {
      let tempSequence: string[] = []
      let tempCompSizeMap: Map<string, CompSize> = new Map
      this.MaxHeight = 0
      this.MaxWidth = 0
      this.comp_sequence.forEach((type) => {
        let size = this.getCompSize(type)
        let pos: Position = this.findFreeSpace(size.lane_w, size.lane_h, tempSequence, tempCompSizeMap)
        Logger.debug(`updateNewUIType ${type}_${pos.x}_${pos.y}`)
        tempCompSizeMap.set(size.type, new CompSize().setPos(pos.x, pos.y).setSize(size.lane_w, size.lane_h).withType(size.type))
        tempSequence.push(type)
        this.getCompSize(type).setPos(pos.x, pos.y)
        this.MaxHeight = Math.max(this.MaxHeight, pos.y+size.lane_h)
        this.MaxWidth = Math.max(this.MaxWidth, pos.x+size.lane_w)
      })
    }
  }

  LayoutWidth(): number {
    return WindowUtil.uiType
  }

  LayoutHeight(): number {
    return (this.comp_sequence.length+1)*2
  }

  getCompSize(type: string): CompSize {
    if (this.compSizeMap.has(type)) {
      return this.compSizeMap.get(type)!
    }else {
      return new CompSize().withType(type)
    }
  }

  isOutOfBounds(x: number, y: number, w: number, h: number): boolean {
    return x < 0 ||
      y < 0 ||
      x + w > this.LayoutWidth() ||
      y + h > this.LayoutHeight();
  }

  isOverlap(comp1: CompSize, comp2: CompSize): boolean {
    if (comp1 === comp2) return false;

    const comp1Right = comp1.grid_x + comp1.lane_w;
    const comp1Bottom = comp1.grid_y + comp1.lane_h;
    const comp2Right = comp2.grid_x + comp2.lane_w;
    const comp2Bottom = comp2.grid_y + comp2.lane_h;

    return comp1.grid_x < comp2Right &&
      comp1Right > comp2.grid_x &&
      comp1.grid_y < comp2Bottom &&
      comp1Bottom > comp2.grid_y;
  }

  updateGridPosition(pos: Position, width: number, height: number): Position {
    const a = lane(1);
    const period = a + 10;
    const regionWidth = width * a + (width - 1) * 10;
    const regionHeight = height * a + (height - 1) * 10;
    const floatLeft = pos.x;
    const floatRight = pos.x + regionWidth;
    const floatBottom = pos.y;
    const floatTop = pos.y + regionHeight;
    const startX = Math.floor(floatLeft / period) * period;
    const endX = Math.ceil(floatRight / period) * period;
    const startY = Math.floor(floatBottom / period) * period;
    const endY = Math.ceil(floatTop / period) * period;
    for (let baseX = startX; baseX <= endX; baseX += period) {
      for (let baseY = startY; baseY <= endY; baseY += period) {
        const targetLeft = baseX;
        const targetRight = baseX + regionWidth;
        const targetBottom = baseY;
        const targetTop = baseY + regionHeight;
        const overlapLeft = Math.max(floatLeft, targetLeft);
        const overlapRight = Math.min(floatRight, targetRight);
        const overlapBottom = Math.max(floatBottom, targetBottom);
        const overlapTop = Math.min(floatTop, targetTop);
        if (overlapLeft < overlapRight && overlapBottom < overlapTop) {
          const overlapWidth = overlapRight - overlapLeft;
          const overlapHeight = overlapTop - overlapBottom;
          const overlapArea = overlapWidth * overlapHeight;
          const totalArea = regionWidth * regionHeight;
          if (overlapArea >= 0.6 * totalArea) {
            const baseGridX = preciseIntegerDivision(baseX, period);
            const baseGridY = preciseIntegerDivision(baseY, period);
            return { x: baseGridX, y: baseGridY };
          }
        }
      }
    }
    return { x: -1, y: -1 };
  }

  confirmTempPos() {
    this.comp_sequence.forEach((comp) => {
      let compSize = this.getCompSize(comp)
      if (compSize.find_next_grid) {
        AppManager.content.uiContext?.postFrameCallback(new MyFrameCallback(() => {
          compSize.find_next_grid = false
          compSize.grid_x = compSize.next_grid_x
          compSize.grid_y = compSize.next_grid_y
        }));
      }
    })
  }

  cancelTempPos() {
    this.comp_sequence.forEach((comp) => {
      let compSize = this.getCompSize(comp)
      if (compSize.find_next_grid) {
        animateToImmediately(layoutAnimationParm, () => {
          compSize.find_next_grid = false
        })
      }
    })
  }

  updateSequence() {
    let sequenceData = ""
    this.MaxHeight = 0
    this.comp_sequence.sort((a,b) => {
      let size1 = this.getCompSize(a)
      let size2 = this.getCompSize(b)
      if (size1.grid_y !== size2.grid_y) {
        return size1.grid_y - size2.grid_y;
      }
      return size1.grid_x - size2.grid_x;
    }).forEach((value) => {
      let size = this.getCompSize(value)
      this.MaxHeight = Math.max(this.MaxHeight, size.grid_y+size.lane_h)
      sequenceData += `${value}_${size.grid_x}_${size.grid_y}_${size.lane_w}_${size.lane_h}|`
    })
    AppManager.preference.updateSequence(sequenceData.length>0?sequenceData.substring(0,sequenceData.length-1):sequenceData)
  }

  getObstacles(comp_name: string, pos: Position, width: number, height: number): string[] {
    let overlapComps: string[] = []
    for (const comp of this.comp_sequence) {
      if (comp === comp_name) continue
      let size = this.getCompSize(comp)
      const overlapLeft = Math.max(pos.x, size.grid_x);
      const overlapRight = Math.min(pos.x+width, size.grid_x+size.lane_w);
      const overlapBottom = Math.max(pos.y, size.grid_y);
      const overlapTop = Math.min(pos.y+height, size.grid_y+size.lane_h);
      if (overlapLeft < overlapRight && overlapBottom < overlapTop) {
        overlapComps.push(comp)
      }
    }
    return overlapComps
  }

  pushObstacle(comp_name: string, pos: Position, width: number, height: number) {
    let overlapComps: string[] = this.getObstacles(comp_name, pos, width, height)
    overlapComps.sort((a,b) => {
      let size1 = this.getCompSize(a)
      let size2 = this.getCompSize(b)
      if (size1.grid_y !== size2.grid_y) {
        return size1.grid_y - size2.grid_y;
      }
      return size1.grid_x - size2.grid_x;
    })
    overlapComps.forEach((comp) => {
      let compSize = this.getCompSize(comp)
      let tempPos = this.findFreeSpace(compSize.lane_w, compSize.lane_h)
      if (tempPos.x >= 0) {
        animateToImmediately(layoutAnimationParm, () => {
          compSize.find_next_grid = true
          compSize.next_grid_x = tempPos.x
          compSize.next_grid_y = tempPos.y
        })
      }else {
        this.comp_sequence.splice(this.comp_sequence.indexOf(comp_name))
      }
    })
  }

  canPlaceAt(
    x: number,
    y: number,
    w: number,
    h: number,
    overrideSequence: string[] = this.comp_sequence,
    overrideCompSize: Map<string, CompSize> | undefined
  ): boolean {
    for (const comp of overrideSequence) {
      let compSize = overrideCompSize?overrideCompSize.get(comp)!:this.getCompSize(comp)
      let comp_x = compSize.find_next_grid?compSize.next_grid_x:compSize.grid_x;
      let comp_y = compSize.find_next_grid?compSize.next_grid_y:compSize.grid_y;
      const overlap =
        !(x + w <= comp_x ||
          comp_x + compSize.lane_w <= x ||
          y + h <= comp_y ||
          comp_y + compSize.lane_h <= y);
      if (overlap) {
        return false;
      }
    }
    return true;
  }

  findFreeSpace(
    itemW: number,
    itemH: number,
    overrideSequence: string[] = this.comp_sequence,
    overrideCompSize: Map<string, CompSize> | undefined = undefined
  ): Position {
    for (let y = 0; y + itemH <= this.LayoutHeight(); y++) {
      for (let x = 0; x + itemW <= this.LayoutWidth(); x++) {
        if (this.canPlaceAt(x, y, itemW, itemH, overrideSequence, overrideCompSize)) {
          return { x:x, y:y };
        }
      }
    }
    return { x:-1, y:-1 };
  }
}