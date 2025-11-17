import { WindowUtil } from "./WindowUtil"

@ObservedV2
export class CompSize {
  @Trace lane_w: number = 1
  @Trace lane_h: number = 1
  @Trace offset_l: number = 0
  @Trace offset_r: number = 0
  @Trace offset_u: number = 0
  @Trace offset_d: number = 0
  @Trace x: number = 0
  @Trace y: number = 0
  @Trace isFloating: boolean = false
  @Trace floatingX: number = 0
  @Trace floatingY: number = 0
}

export interface WillOverlapResult { willOverlap: boolean; overlappingComps: string[] }
export interface IsValidResizeResult { isValid: boolean; reason?: string }
export interface Position { x: number; y: number }

@ObservedV2
export class LayoutUtil {
  @Trace public static comp_sequence: string[] = ["Instances", "GlobalConfigs", "Logs"]
  @Trace public static InstancesSize: CompSize = new CompSize()
  @Trace public static GlobalConfigsSize: CompSize = new CompSize()
  @Trace public static LogsSize: CompSize = new CompSize()

  public static readonly MIN_COMP_WIDTH = 1;
  public static readonly MIN_COMP_HEIGHT = 1;

  public static getCompSize(type: string): CompSize {
    switch (type) {
      case "Instances" : return LayoutUtil.InstancesSize
      case "GlobalConfigs": return LayoutUtil.GlobalConfigsSize
      case "Logs": return LayoutUtil.LogsSize
      default : return new CompSize()
    }
  }

  public static isOutOfBounds(compSize: CompSize): boolean {
    return compSize.x < 0 ||
      compSize.y < 0 ||
      compSize.x + compSize.lane_w > WindowUtil.uiType ||
      compSize.y + compSize.lane_h > 10;
  }

  public static isTooSmall(compSize: CompSize): boolean {
    return compSize.lane_w < LayoutUtil.MIN_COMP_WIDTH || compSize.lane_h < LayoutUtil.MIN_COMP_HEIGHT;
  }

  public static isOverlap(comp1: CompSize, comp2: CompSize): boolean {
    if (comp1 === comp2) return false;

    const comp1Right = comp1.x + comp1.lane_w;
    const comp1Bottom = comp1.y + comp1.lane_h;
    const comp2Right = comp2.x + comp2.lane_w;
    const comp2Bottom = comp2.y + comp2.lane_h;

    return comp1.x < comp2Right &&
      comp1Right > comp2.x &&
      comp1.y < comp2Bottom &&
      comp1Bottom > comp2.y;
  }

  public static willOverlapAfterResize(
    targetComp: CompSize,
    newWidth: number,
    newHeight: number
  ): WillOverlapResult{
    const overlappingComps: string[] = [];

    // 创建临时尺寸对象用于检测
    const tempSize = new CompSize();
    tempSize.x = targetComp.x;
    tempSize.y = targetComp.y;
    tempSize.lane_w = newWidth;
    tempSize.lane_h = newHeight;

    // 检查所有其他组件
    for (const compType of LayoutUtil.comp_sequence) {
      const compSize = LayoutUtil.getCompSize(compType);
      if (compSize !== targetComp && LayoutUtil.isOverlap(tempSize, compSize)) {
        overlappingComps.push(compType);
      }
    }

    return {
      willOverlap: overlappingComps.length > 0,
      overlappingComps: overlappingComps
    };
  }

  public static pushOverlappingComponents(movedComp: CompSize, movedCompType: string): void {
    const movedRight = movedComp.x + movedComp.lane_w;
    const movedBottom = movedComp.y + movedComp.lane_h;

    for (const compType of LayoutUtil.comp_sequence) {
      if (compType === movedCompType) continue;

      const compSize = LayoutUtil.getCompSize(compType);
      if (LayoutUtil.isOverlap(movedComp, compSize)) {
        // 计算重叠区域
        const overlapRight = Math.min(movedRight, compSize.x + compSize.lane_w);
        const overlapBottom = Math.min(movedBottom, compSize.y + compSize.lane_h);
        const overlapLeft = Math.max(movedComp.x, compSize.x);
        const overlapTop = Math.max(movedComp.y, compSize.y);

        const overlapWidth = overlapRight - overlapLeft;
        const overlapHeight = overlapBottom - overlapTop;

        // 决定推动方向（优先向右，其次向下）
        if (compSize.x + compSize.lane_w + overlapWidth <= WindowUtil.uiType) {
          // 向右推动
          compSize.x += overlapWidth;
        } else if (compSize.y + compSize.lane_h + overlapHeight <= 10) {
          // 向下推动
          compSize.y += overlapHeight;
        } else {
          // 如果无法推动，尝试向左上角寻找空位
          LayoutUtil.findEmptySpace(compSize);
        }

        // 递归检查推动后的组件是否又与其他组件重叠
        LayoutUtil.pushOverlappingComponents(compSize, compType);
      }
    }
  }

  private static findEmptySpace(compSize: CompSize): void {
    for (let y = 0; y <= 10 - compSize.lane_h; y++) {
      for (let x = 0; x <= WindowUtil.uiType - compSize.lane_w; x++) {
        const tempSize = new CompSize();
        tempSize.x = x;
        tempSize.y = y;
        tempSize.lane_w = compSize.lane_w;
        tempSize.lane_h = compSize.lane_h;

        let hasOverlap = false;
        for (const compType of LayoutUtil.comp_sequence) {
          const otherComp = LayoutUtil.getCompSize(compType);
          if (otherComp !== compSize && LayoutUtil.isOverlap(tempSize, otherComp)) {
            hasOverlap = true;
            break;
          }
        }

        if (!hasOverlap) {
          compSize.x = x;
          compSize.y = y;
          return;
        }
      }
    }
  }

  public static isValidResize(
    targetComp: CompSize,
    newWidth: number,
    newHeight: number
  ): IsValidResizeResult {
    // 检查最小尺寸
    if (newWidth < LayoutUtil.MIN_COMP_WIDTH || newHeight < LayoutUtil.MIN_COMP_HEIGHT) {
      return { isValid: false, reason: "组件尺寸不能小于最小值" };
    }

    // 检查边界
    if (targetComp.x + newWidth > WindowUtil.uiType || targetComp.y + newHeight > 10) {
      return { isValid: false, reason: "组件超出边界" };
    }

    // 检查重叠
    const overlapCheck = LayoutUtil.willOverlapAfterResize(targetComp, newWidth, newHeight);
    if (overlapCheck.willOverlap) {
      return {
        isValid: false,
        reason: `与组件 ${overlapCheck.overlappingComps.join(', ')} 重叠`
      };
    }

    return { isValid: true };
  }
}