import { lane } from "./util/Conversion"
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
}

export interface Position { x: number, y: number}

@ObservedV2
export class LayoutUtil {
  @Trace public static comp_sequence: string[] = ["Instances"]
  @Trace public static InstancesSize: CompSize = new CompSize()
  @Trace public static GlobalConfigsSize: CompSize = new CompSize()
  @Trace public static LogsSize: CompSize = new CompSize()

  public static readonly MIN_COMP_WIDTH = 1;
  public static readonly MIN_COMP_HEIGHT = 1;

  public static LayoutWidth(): number {
    return WindowUtil.uiType
  }

  public static LayoutHeight(): number {
    return 10
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

    // 当前浮动区域的像素尺寸和范围
    const regionWidth = width * a + (width - 1) * 10;
    const regionHeight = height * a + (height - 1) * 10;

    const floatLeft = pos.x;
    const floatRight = pos.x + regionWidth;
    const floatBottom = pos.y;
    const floatTop = pos.y + regionHeight;

    // 目标区域的左下角必须是 period 的整数倍
    // 找出所有可能的目标区域左下角
    const startX = Math.floor(floatLeft / period) * period;
    const endX = Math.ceil(floatRight / period) * period;
    const startY = Math.floor(floatBottom / period) * period;
    const endY = Math.ceil(floatTop / period) * period;

    // 检查所有可能的目标区域
    for (let baseX = startX; baseX <= endX; baseX += period) {
      for (let baseY = startY; baseY <= endY; baseY += period) {
        // 目标区域的像素范围
        const targetLeft = baseX;
        const targetRight = baseX + regionWidth;
        const targetBottom = baseY;
        const targetTop = baseY + regionHeight;

        // 计算重叠区域
        const overlapLeft = Math.max(floatLeft, targetLeft);
        const overlapRight = Math.min(floatRight, targetRight);
        const overlapBottom = Math.max(floatBottom, targetBottom);
        const overlapTop = Math.min(floatTop, targetTop);

        if (overlapLeft < overlapRight && overlapBottom < overlapTop) {
          const overlapWidth = overlapRight - overlapLeft;
          const overlapHeight = overlapTop - overlapBottom;
          const overlapArea = overlapWidth * overlapHeight;

          // 计算总面积
          const totalArea = regionWidth * regionHeight;

          // 检查是否达到60%重叠
          if (overlapArea >= 0.6 * totalArea) {
            // 将目标区域左下角转换回小格子坐标
            const baseGridX = baseX / period;
            const baseGridY = baseY / period;
            return { x: baseGridX, y: baseGridY };
          }
        }
      }
    }

    return { x: -1, y: -1 };
  }
}