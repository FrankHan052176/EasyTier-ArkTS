export enum UIType {
  Column_1, Column_2, Column_3
}

@ObservedV2
class WindowUtil {
  @Trace public static width: number = 0
  @Trace public static height: number = 0
  @Trace public static uiType: UIType = UIType.Column_1
  @Trace public static context: Context | undefined

  public static update(width: number, height: number) {
    WindowUtil.width = width
    WindowUtil.height = height
    if (condition) {
      
    }
  }
}