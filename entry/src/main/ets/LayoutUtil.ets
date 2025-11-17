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
}

@ObservedV2
export class LayoutUtil {
  @Trace public static comp_sequence: string[] = ["Instances", "GlobalConfigs"]
  @Trace public static InstancesSize: CompSize = new CompSize()
  @Trace public static GlobalConfigsSize: CompSize = new CompSize()
  @Trace public static LogsSize: CompSize = new CompSize()

  public static getCompSize(type: string): CompSize {
    switch (type) {
      case "Instances" : return LayoutUtil.InstancesSize
      case "GlobalConfigs": return LayoutUtil.GlobalConfigsSize
      case "Logs": return LayoutUtil.LogsSize
      default : return new CompSize()
    }
  }
}