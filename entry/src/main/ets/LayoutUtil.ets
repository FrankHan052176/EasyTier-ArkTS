import { AutoSortContainer } from "./pages/nodes/AutoSortContainer"
import { layoutAnimationParm } from "./pages/nodes/ResizableComponent"
import { lane } from "./util/Conversion"
import { EventHelper } from "./util/EventHelper"
import { Logger } from "./util/Logger"
import { WindowUtil } from "./WindowUtil"

@ObservedV2
export class CompSize {
  @Trace lane_w: number = 1
  @Trace lane_h: number = 1
  @Trace offset_l: number = 0
  @Trace offset_r: number = 0
  @Trace offset_u: number = 0
  @Trace offset_d: number = 0
  @Trace grid_x: number = 0
  @Trace grid_y: number = 0
  @Trace isFloating: boolean = false
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
}

export interface Position { x: number, y: number}

@ObservedV2
export class LayoutUtil {
  public static myNodeController: AutoSortContainer = new AutoSortContainer();
  @Trace public static comp_sequence: string[] = false?["Instances"]:["Instances", "GlobalConfigs", "Logs"]
  @Trace public static InstancesSize: CompSize = new CompSize()
  @Trace public static GlobalConfigsSize: CompSize = new CompSize().setPos(1,0)
  @Trace public static LogsSize: CompSize = new CompSize().setPos(0,1)

  public static readonly MIN_COMP_WIDTH = 1;
  public static readonly MIN_COMP_HEIGHT = 1;

  public static LayoutWidth(): number {
    return WindowUtil.uiType
  }

  public static LayoutHeight(): number {
    return (LayoutUtil.comp_sequence.length+1)*2
  }

  public static getCompSize(type: string): CompSize {
    switch (type) {
      case "Instances" : return LayoutUtil.InstancesSize
      case "GlobalConfigs": return LayoutUtil.GlobalConfigsSize
      case "Logs": return LayoutUtil.LogsSize
      default : return new CompSize()
    }
  }

  public static isOutOfBounds(compSize: CompSize): boolean {
    return compSize.grid_x < 0 ||
      compSize.grid_y < 0 ||
      compSize.grid_x + compSize.lane_w > LayoutUtil.LayoutWidth() ||
      compSize.grid_y + compSize.lane_h > LayoutUtil.LayoutHeight();
  }

  public static isOverlap(comp1: CompSize, comp2: CompSize): boolean {
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

  public static updateGridPosition(pos: Position, width: number, height: number): Position {
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
            const baseGridX = baseX / period;
            const baseGridY = baseY / period;
            return { x: baseGridX, y: baseGridY };
          }
        }
      }
    }
    return { x: -1, y: -1 };
  }
  public static confirmTempPos() {
    LayoutUtil.comp_sequence.forEach((comp) => {
      let compSize = LayoutUtil.getCompSize(comp)
      if (compSize.find_next_grid) {
        compSize.find_next_grid = false
        compSize.grid_x = compSize.next_grid_x
        compSize.grid_y = compSize.next_grid_y
      }
    })
    LayoutUtil.myNodeController.rootNode?.setNeedsLayout()
  }

  public static cancelTempPos() {
    LayoutUtil.comp_sequence.forEach((comp) => {
      let compSize = LayoutUtil.getCompSize(comp)
      if (compSize.find_next_grid) {
        animateToImmediately(layoutAnimationParm, () => {
          compSize.find_next_grid = false
        })
      }
    })
  }

  public static getObstacles(comp_name: string, pos: Position, width: number, height: number): string[] {
    let overlapComps: string[] = []
    for (const comp of LayoutUtil.comp_sequence) {
      if (comp === comp_name) continue
      let size = LayoutUtil.getCompSize(comp)
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

  public static pushObstacle(comp_name: string, pos: Position, width: number, height: number) {
    let overlapComps: string[] = LayoutUtil.getObstacles(comp_name, pos, width, height)
    overlapComps.sort((a,b) => {
      let size1 = LayoutUtil.getCompSize(a)
      let size2 = LayoutUtil.getCompSize(b)
      if (size1.grid_y !== size2.grid_y) {
        return size1.grid_y - size2.grid_y;
      }
      return size1.grid_x - size2.grid_x;
    })
    overlapComps.forEach((comp) => {
      let compSize = LayoutUtil.getCompSize(comp)
      let tempPos = LayoutUtil.findFreeSpace(compSize.lane_w, compSize.lane_h)
      if (tempPos.x >= 0) {
        animateToImmediately(layoutAnimationParm, () => {
          compSize.find_next_grid = true
          compSize.next_grid_x = tempPos.x
          compSize.next_grid_y = tempPos.y
        })
      }
    })
  }

  public static canPlaceAt(
    x: number,
    y: number,
    w: number,
    h: number
  ): boolean {
    for (const comp of LayoutUtil.comp_sequence) {
      let compSize = LayoutUtil.getCompSize(comp)
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

  public static findFreeSpace(
    itemW: number,
    itemH: number
  ): Position {
    for (let y = 0; y + itemH <= LayoutUtil.LayoutHeight(); y++) {
      for (let x = 0; x + itemW <= LayoutUtil.LayoutWidth(); x++) {
        if (LayoutUtil.canPlaceAt(x, y, itemW, itemH)) {
          return { x, y };
        }
      }
    }
    return { x:-1, y:-1 };
  }
}