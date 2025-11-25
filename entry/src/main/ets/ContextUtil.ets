import { Context } from "@kit.AbilityKit"
import { Logger, LogLocate } from "./util/Logger"
import { MeasureUtils } from "@kit.ArkUI"

@LogLocate("ContextUtil")
@ObservedV2
export class ContextUtil {
  @Trace uiContext: UIContext | undefined
  @Trace context: Context | undefined
  @Trace measure: MeasureUtils | undefined

  init(uiContext: UIContext) {
    this.uiContext = uiContext
    Logger.info("init uiContext and context", this)
    this.context = uiContext.getHostContext()
    this.measure = uiContext.getMeasureUtils()
  }
}