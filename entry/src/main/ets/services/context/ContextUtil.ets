import { Context } from '@kit.AbilityKit'
import { Logger, LogLocate } from '../../shared/logging/Logger'
import { MeasureUtils } from '@kit.ArkUI'
import { distributedDeviceManager } from '@kit.DistributedServiceKit'
import { APP_BUNDLE_NAME } from '../runtime/AbilityRuntimePolicy'

@LogLocate("ContextUtil")
@ObservedV2
export class ContextUtil {
  deviceManager: distributedDeviceManager.DeviceManager =
    distributedDeviceManager.createDeviceManager(APP_BUNDLE_NAME)
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
