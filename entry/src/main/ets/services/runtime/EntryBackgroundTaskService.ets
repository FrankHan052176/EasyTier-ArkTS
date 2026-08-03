import { WantAgent, common, wantAgent } from '@kit.AbilityKit'
import { backgroundTaskManager } from '@kit.BackgroundTasksKit'
import { JSON } from '@kit.ArkTS'
import { BusinessError, deviceInfo } from '@kit.BasicServicesKit'
import { Logger } from '../../shared/logging/Logger'
import { sendToast } from '../../ToastUtil'
import { publishTextNotification } from '../../util/NoticeHelper'
import {
  BACKGROUND_KEEP_ALIVE_AUDIO_PLAYBACK,
  BACKGROUND_KEEP_ALIVE_DATA_TRANSFER,
  BACKGROUND_KEEP_ALIVE_TASK_KEEPING,
  BackgroundKeepAliveMode,
  normalizeBackgroundKeepAliveMode
} from '../../types/runtime/BackgroundKeepAliveTypes'
import { AudioKeepAliveService } from './AudioKeepAliveService'
import {
  APP_BUNDLE_NAME,
  CONTINUOUS_BACKGROUND_TASK_SYSCAP,
  ENTRY_ABILITY_NAME
} from './AbilityRuntimePolicy'

export interface EntryBackgroundTaskServiceOptions {
  context: common.UIAbilityContext
  logTarget: Object | string
  setNotificationId: (notificationId: number) => void
  clearNotificationId: () => void
  getBackgroundKeepAliveMode: () => string
  onBackgroundTaskCancelled?: (reason: string) => void
  onBackgroundTaskSuspended?: (reason: string) => void
  onBackgroundTaskActive?: () => void
}

export class EntryBackgroundTaskService {
  private readonly context: common.UIAbilityContext
  private readonly logTarget: Object | string
  private readonly setNotificationId: (notificationId: number) => void
  private readonly clearNotificationId: () => void
  private readonly getBackgroundKeepAliveMode: () => string
  private readonly onBackgroundTaskCancelled: (reason: string) => void
  private readonly onBackgroundTaskSuspended: (reason: string) => void
  private readonly onBackgroundTaskActive: () => void
  private readonly audioKeepAliveService: AudioKeepAliveService
  private monitoringRegistered: boolean = false
  private runtimeGeneration: number = 0
  private activeContinuousTaskId: number | undefined = undefined
  private hasActiveContinuousTask: boolean = false
  private stoppingContinuousTask: boolean = false
  private lastKeepAliveMode: BackgroundKeepAliveMode = BACKGROUND_KEEP_ALIVE_DATA_TRANSFER
  private lastTaskName: string = 'EasyTier'
  private readonly continuousTaskCancelCallback = (info: backgroundTaskManager.ContinuousTaskCancelInfo): void => {
    if (!this.isCurrentContinuousTask(info.id)) {
      return
    }
    const reason = `${info.reason}`
    Logger.error(`continuous task cancelled id=${info.id} reason=${reason}`, this.logTarget)
    this.audioKeepAliveService.stop()
    this.hasActiveContinuousTask = false
    this.activeContinuousTaskId = undefined
    this.clearNotificationId()
    this.onBackgroundTaskCancelled(reason)
  }
  private readonly continuousTaskSuspendCallback = (info: backgroundTaskManager.ContinuousTaskSuspendInfo): void => {
    if (!this.isCurrentContinuousTask(info.continuousTaskId)) {
      return
    }
    Logger.warn(`continuous task suspend id=${info.continuousTaskId} state=${info.suspendState} reason=${info.suspendReason}`,
      this.logTarget)
    if (info.suspendState) {
      this.onBackgroundTaskSuspended(`${info.suspendReason}`)
    }
  }
  private readonly continuousTaskActiveCallback = (info: backgroundTaskManager.ContinuousTaskActiveInfo): void => {
    if (!this.isCurrentContinuousTask(info.id)) {
      return
    }
    Logger.info(`continuous task active id=${info.id}`, this.logTarget)
    this.onBackgroundTaskActive()
  }

  constructor(options: EntryBackgroundTaskServiceOptions) {
    this.context = options.context
    this.logTarget = options.logTarget
    this.setNotificationId = options.setNotificationId
    this.clearNotificationId = options.clearNotificationId
    this.getBackgroundKeepAliveMode = options.getBackgroundKeepAliveMode
    this.onBackgroundTaskCancelled = options.onBackgroundTaskCancelled ?? (() => {})
    this.onBackgroundTaskSuspended = options.onBackgroundTaskSuspended ?? (() => {})
    this.onBackgroundTaskActive = options.onBackgroundTaskActive ?? (() => {})
    this.audioKeepAliveService = new AudioKeepAliveService(options.logTarget)
    this.registerTaskMonitoring()
  }

  private isCurrentContinuousTask(taskId: number | undefined): boolean {
    if (this.stoppingContinuousTask || !this.hasActiveContinuousTask) {
      return false
    }
    if (this.activeContinuousTaskId === undefined) {
      return taskId === undefined
    }
    return taskId === this.activeContinuousTaskId
  }

  private async stopBackgroundTask(taskId: number | undefined): Promise<void> {
    if (taskId !== undefined && deviceInfo.sdkApiVersion >= 21) {
      await backgroundTaskManager.stopBackgroundRunning(this.context, taskId)
      return
    }
    await backgroundTaskManager.stopBackgroundRunning(this.context)
  }

  private registerTaskMonitoring(): void {
    if (this.monitoringRegistered || !canIUse(CONTINUOUS_BACKGROUND_TASK_SYSCAP)) {
      return
    }
    try {
      backgroundTaskManager.on('continuousTaskCancel', this.continuousTaskCancelCallback)
      backgroundTaskManager.on('continuousTaskSuspend', this.continuousTaskSuspendCallback)
      backgroundTaskManager.on('continuousTaskActive', this.continuousTaskActiveCallback)
      this.monitoringRegistered = true
    } catch (error) {
      Logger.error(`continuous task monitor registration failed: ${JSON.stringify(error)}`, this.logTarget)
    }
  }

  stopTaskMonitoring(): void {
    if (!this.monitoringRegistered) {
      return
    }
    try {
      backgroundTaskManager.off('continuousTaskCancel', this.continuousTaskCancelCallback)
      backgroundTaskManager.off('continuousTaskSuspend', this.continuousTaskSuspendCallback)
      backgroundTaskManager.off('continuousTaskActive', this.continuousTaskActiveCallback)
    } catch (error) {
      Logger.debug(`continuous task monitor cleanup failed: ${JSON.stringify(error)}`, this.logTarget)
    }
    this.monitoringRegistered = false
  }

  async startContinuousTask(name: string | undefined): Promise<boolean> {
    this.lastKeepAliveMode = normalizeBackgroundKeepAliveMode(this.getBackgroundKeepAliveMode())
    if (this.lastKeepAliveMode === BACKGROUND_KEEP_ALIVE_TASK_KEEPING) {
      this.lastKeepAliveMode = BACKGROUND_KEEP_ALIVE_DATA_TRANSFER
    }
    this.lastTaskName = name ?? 'EasyTier'
    if (this.hasActiveContinuousTask) {
      publishTextNotification(this.lastTaskName)
      return true
    }
    const generation = ++this.runtimeGeneration
    this.clearNotificationId()
    if (this.lastKeepAliveMode === BACKGROUND_KEEP_ALIVE_AUDIO_PLAYBACK) {
      this.audioKeepAliveService.start()
    }
    if (!canIUse(CONTINUOUS_BACKGROUND_TASK_SYSCAP)) {
      Logger.info(`continuous task capability unavailable mode=${this.lastKeepAliveMode}`, this.logTarget)
      return true
    }
    try {
      const wantAgentObj = await this.createWantAgent()
      const modes: string[] = [this.lastKeepAliveMode]
      const result = await backgroundTaskManager.startBackgroundRunning(this.context, modes, wantAgentObj)
      if (generation !== this.runtimeGeneration) {
        await this.stopBackgroundTask(result.continuousTaskId)
        return false
      }
      this.activeContinuousTaskId = result.continuousTaskId
      this.hasActiveContinuousTask = true
      this.setNotificationId(result.notificationId)
      publishTextNotification(this.lastTaskName)
      Logger.info(`continuous task started id=${result.continuousTaskId ?? -1} mode=${this.lastKeepAliveMode}`,
        this.logTarget)
      return true
    } catch (error) {
      const err = error as BusinessError
      this.audioKeepAliveService.stop()
      sendToast('后台保活启动失败，请尝试切换保活模式。', $r('sys.symbol.exclamationmark_circle'), 1)
      Logger.error(`startBackgroundRunning ${this.lastKeepAliveMode} failed: ${err.code}, ${err.message}`,
        this.logTarget)
      return false
    }
  }

  private createWantAgent(): Promise<WantAgent> {
    const wantAgentInfo: wantAgent.WantAgentInfo = {
      wants: [
        {
          bundleName: APP_BUNDLE_NAME,
          abilityName: ENTRY_ABILITY_NAME
        }
      ],
      actionType: wantAgent.OperationType.START_ABILITY,
      requestCode: 0,
      actionFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
    }
    return wantAgent.getWantAgent(wantAgentInfo)
  }

  async stopContinuousTask(): Promise<void> {
    this.runtimeGeneration++
    this.stoppingContinuousTask = true
    this.audioKeepAliveService.stop()
    const taskId = this.activeContinuousTaskId
    try {
      if (this.hasActiveContinuousTask && canIUse(CONTINUOUS_BACKGROUND_TASK_SYSCAP)) {
        await this.stopBackgroundTask(taskId)
      }
    } finally {
      this.hasActiveContinuousTask = false
      this.activeContinuousTaskId = undefined
      this.stoppingContinuousTask = false
      this.clearNotificationId()
    }
  }
}
