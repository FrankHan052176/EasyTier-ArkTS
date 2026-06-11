import { common } from '@kit.AbilityKit'
import { deviceInfo } from '@kit.BasicServicesKit'
import { AppManager } from '../../AppManager'
import { Logger } from '../../shared/logging/Logger'
import { MemoryDiagnosticsService } from './MemoryDiagnosticsService'

export interface EntryAppBootstrapServiceOptions {
  context: common.UIAbilityContext
  logTarget: Object | string
  syncContinuationSocket: () => void
}

export class EntryAppBootstrapService {
  private readonly context: common.UIAbilityContext
  private readonly logTarget: Object | string
  private readonly syncContinuationSocket: () => void

  constructor(options: EntryAppBootstrapServiceOptions) {
    this.context = options.context
    this.logTarget = options.logTarget
    this.syncContinuationSocket = options.syncContinuationSocket
  }

  async initialize(): Promise<void> {
    AppManager.uiState.init()
    AppManager.uiState.setSocketFilesDir(this.context.filesDir)
    try {
      await AppManager.preference.init(this.context)
    } catch (error) {
      Logger.error(`PreferenceUtil failed to init.\n${error}`, this.logTarget)
      return
    }
    if (AppManager.uiState.debug_log) {
      MemoryDiagnosticsService.enableSystemLeakWatcher(true)
      MemoryDiagnosticsService.markDelayed('EntryAbility.preference.init')
    }
    await AppManager.data.init()
    if (AppManager.uiState.debug_log) {
      MemoryDiagnosticsService.markDelayed('EntryAbility.data.init')
    }
    if (deviceInfo.productModel !== "emulator") {
      AppManager.easytier.init()
    }
    if (AppManager.uiState.debug_log) {
      MemoryDiagnosticsService.markDelayed('EntryAbility.easytier.init')
    }
    this.syncContinuationSocket()
  }
}
