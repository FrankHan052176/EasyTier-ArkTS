import { WantAgent, common, wantAgent } from '@kit.AbilityKit'
import { backgroundTaskManager } from '@kit.BackgroundTasksKit'
import { JSON } from '@kit.ArkTS'
import { BusinessError, deviceInfo } from '@kit.BasicServicesKit'
import { HMRouterMgr } from '@hadss/hmrouter'
import { BottomAnimator } from '../../class/animator/BottomAnimator'
import { ConfigJson } from '../../config/schema/SchemaConfig'
import { Logger } from '../../shared/logging/Logger'
import { sendToast } from '../../ToastUtil'
import { publishTextNotification } from '../../util/NoticeHelper'
import { AudioKeepAliveService } from './AudioKeepAliveService'
import { startRuntimeStatsRecording, stopRuntimeStatsRecording } from './RuntimeStatsService'
import {
  BACKGROUND_KEEP_ALIVE_AUDIO_PLAYBACK,
  BACKGROUND_KEEP_ALIVE_DATA_TRANSFER,
  BackgroundKeepAliveMode,
  normalizeBackgroundKeepAliveMode
} from '../../types/runtime/BackgroundKeepAliveTypes'
import {
  APP_BUNDLE_NAME,
  CONTINUOUS_BACKGROUND_TASK_SYSCAP,
  ENTRY_ABILITY_NAME
} from './AbilityRuntimePolicy'

export interface EntryBackgroundTaskServiceOptions {
  context: common.UIAbilityContext
  logTarget: Object | string
  runNetworkInstance: (cfg: string) => boolean
  activateMissionContinue: () => void
  deactivateMissionContinue: () => void
  refreshFavoriteCard: () => void
  setNotificationId: (notificationId: number) => void
  clearNotificationId: () => void
  destroyVpnConnection: () => Promise<void>
  getBackgroundKeepAliveMode: () => string
  shouldUseBackgroundKeepAlive: () => boolean
  onBackgroundTaskCancelled?: (reason: string) => void
  onBackgroundTaskSuspended?: (reason: string) => void
  onBackgroundTaskActive?: () => void
}

export class EntryBackgroundTaskService {
  private readonly context: common.UIAbilityContext
  private readonly logTarget: Object | string
  private readonly runNetworkInstance: (cfg: string) => boolean
  private readonly activateMissionContinue: () => void
  private readonly deactivateMissionContinue: () => void
  private readonly refreshFavoriteCard: () => void
  private readonly setNotificationId: (notificationId: number) => void
  private readonly clearNotificationId: () => void
  private readonly destroyVpnConnection: () => Promise<void>
  private readonly getBackgroundKeepAliveMode: () => string
  private readonly shouldUseBackgroundKeepAlive: () => boolean
  private readonly onBackgroundTaskCancelled: (reason: string) => void
  private readonly onBackgroundTaskSuspended: (reason: string) => void
  private readonly onBackgroundTaskActive: () => void
  private readonly audioKeepAliveService: AudioKeepAliveService
  private monitoringRegistered: boolean = false
  private runtimeGeneration: number = 0
  private activeContinuousTaskId: number | undefined = undefined
  private hasActiveContinuousTask: boolean = false
  private stoppingContinuousTask: boolean = false
  private continuousTaskRecoveryInFlight: boolean = false
  private lastKeepAliveMode: BackgroundKeepAliveMode = BACKGROUND_KEEP_ALIVE_DATA_TRANSFER
  private lastTaskName: string = 'N/A'
  private readonly continuousTaskCancelCallback = (info: backgroundTaskManager.ContinuousTaskCancelInfo): void => {
    if (!this.isCurrentContinuousTask(info.id)) {
      Logger.debug(`ignore stale continuous task cancel id=${info.id}`, this.logTarget)
      return
    }
    const reason = `${info.reason}`
    Logger.error(`continuous task cancelled id=${info.id} reason=${reason}`, this.logTarget)
    this.hasActiveContinuousTask = false
    this.activeContinuousTaskId = undefined
    this.clearNotificationId()
    this.onBackgroundTaskCancelled(reason)
    if (info.reason === backgroundTaskManager.ContinuousTaskCancelReason.SYSTEM_CANCEL) {
      void this.recoverContinuousTask()
    }
  }
  private readonly continuousTaskSuspendCallback = (info: backgroundTaskManager.ContinuousTaskSuspendInfo): void => {
    if (!this.isCurrentContinuousTask(info.continuousTaskId)) {
      Logger.debug(`ignore stale continuous task suspend id=${info.continuousTaskId}`, this.logTarget)
      return
    }
    Logger.warn(`continuous task suspend id=${info.continuousTaskId} state=${info.suspendState} reason=${info.suspendReason}`, this.logTarget)
    if (info.suspendState) {
      this.onBackgroundTaskSuspended(`${info.suspendReason}`)
    }
  }
  private readonly continuousTaskActiveCallback = (info: backgroundTaskManager.ContinuousTaskActiveInfo): void => {
    if (!this.isCurrentContinuousTask(info.id)) {
      Logger.debug(`ignore stale continuous task active id=${info.id}`, this.logTarget)
      return
    }
    Logger.info(`continuous task active id=${info.id}`, this.logTarget)
    this.onBackgroundTaskActive()
  }

  constructor(options: EntryBackgroundTaskServiceOptions) {
    this.context = options.context
    this.logTarget = options.logTarget
    this.runNetworkInstance = options.runNetworkInstance
    this.activateMissionContinue = options.activateMissionContinue
    this.deactivateMissionContinue = options.deactivateMissionContinue
    this.refreshFavoriteCard = options.refreshFavoriteCard
    this.setNotificationId = options.setNotificationId
    this.clearNotificationId = options.clearNotificationId
    this.destroyVpnConnection = options.destroyVpnConnection
    this.getBackgroundKeepAliveMode = options.getBackgroundKeepAliveMode
    this.shouldUseBackgroundKeepAlive = options.shouldUseBackgroundKeepAlive
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
      if (canIUse('SystemCapability.ResourceSchedule.BackgroundTaskManager.ContinuousTask')) {
        backgroundTaskManager.on('continuousTaskSuspend', this.continuousTaskSuspendCallback)
        backgroundTaskManager.on('continuousTaskActive', this.continuousTaskActiveCallback)
      }
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

  async startContinuousTask(cfg: string, uuid: string | undefined, name: string | undefined): Promise<boolean> {
    const generation = ++this.runtimeGeneration
    const keepAliveMode = normalizeBackgroundKeepAliveMode(this.getBackgroundKeepAliveMode())
    this.lastKeepAliveMode = keepAliveMode
    this.lastTaskName = name ?? 'N/A'
    this.clearNotificationId()
    if (!this.shouldUseBackgroundKeepAlive()) {
      Logger.info('start runtime without background keep alive', this.logTarget)
      return this.handleRuntimeStartWithoutBackground(cfg, uuid, name, generation)
    }
    if (!canIUse(CONTINUOUS_BACKGROUND_TASK_SYSCAP)) {
      if (keepAliveMode === BACKGROUND_KEEP_ALIVE_AUDIO_PLAYBACK) {
        this.audioKeepAliveService.start()
      }
      return this.handleRuntimeStartWithoutBackground(cfg, uuid, name, generation)
    }
    Logger.info(`start background alive mode=${keepAliveMode}`, this.logTarget)
    if (keepAliveMode === BACKGROUND_KEEP_ALIVE_AUDIO_PLAYBACK) {
      this.audioKeepAliveService.start()
    }
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
    try {
      const wantAgentObj = await wantAgent.getWantAgent(wantAgentInfo)
      return await this.startBackgroundRunning(wantAgentObj, cfg, uuid, name, keepAliveMode, generation)
    } catch (error) {
      const err = error as BusinessError
      this.audioKeepAliveService.stop()
      Logger.error(`getWantAgent failed: ${err.code}, ${err.message}`, this.logTarget)
      return false
    }
  }

  private handleRuntimeStartWithoutBackground(cfg: string, uuid: string | undefined, name: string | undefined,
    generation: number): boolean {
    if (this.runNetworkInstance(cfg)) {
      startRuntimeStatsRecording(this.context.filesDir)
      try {
        const config: ConfigJson = JSON.parse(cfg)
        if (config.no_tun) {
          this.activateMissionContinue()
        }
      } catch (_) {
      }
      setTimeout(() => {
        if (generation !== this.runtimeGeneration) {
          return
        }
        this.refreshFavoriteCard()
      }, 300)
      if (uuid) {
        HMRouterMgr.to('StatusPage')
          .withParam(uuid)
          .withAnimator(new BottomAnimator())
          .pushAsync()
      }
      return true
    } else {
      sendToast("实例启动失败, 可能是内核错误, 请上报日志.", $r("sys.symbol.exclamationmark_circle"), 1)
      Logger.error("启动失败", this.logTarget)
      void this.stopContinuousTask()
      return false
    }
  }

  private async startBackgroundRunning(wantAgentObj: WantAgent, cfg: string, uuid: string | undefined,
    name: string | undefined, keepAliveMode: BackgroundKeepAliveMode, generation: number): Promise<boolean> {
    const modes = keepAliveMode === BACKGROUND_KEEP_ALIVE_AUDIO_PLAYBACK ? [BACKGROUND_KEEP_ALIVE_AUDIO_PLAYBACK] :
      [BACKGROUND_KEEP_ALIVE_DATA_TRANSFER]
    try {
      const res = await backgroundTaskManager.startBackgroundRunning(this.context, modes, wantAgentObj)
      if (generation !== this.runtimeGeneration) {
        Logger.info(`stopping stale continuous task id=${res.continuousTaskId ?? -1}`, this.logTarget)
        await this.stopBackgroundTask(res.continuousTaskId)
        return false
      }
      this.activeContinuousTaskId = res.continuousTaskId
      this.hasActiveContinuousTask = true
      return await this.handleBackgroundRunningStarted(res, cfg, uuid, name, generation)
    } catch (error) {
      const err = error as BusinessError
      this.audioKeepAliveService.stop()
      sendToast("后台保活启动失败，请尝试切换保活模式。", $r("sys.symbol.exclamationmark_circle"), 1)
      Logger.error(`startBackgroundRunning ${keepAliveMode} failed: ${err.code}, ${err.message}`, this.logTarget)
      return false
    }
  }

  private async recoverContinuousTask(): Promise<void> {
    if (this.stoppingContinuousTask || this.continuousTaskRecoveryInFlight || this.hasActiveContinuousTask ||
      !this.shouldUseBackgroundKeepAlive() || !canIUse(CONTINUOUS_BACKGROUND_TASK_SYSCAP)) {
      return
    }
    const generation = this.runtimeGeneration
    this.continuousTaskRecoveryInFlight = true
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
    const modes = this.lastKeepAliveMode === BACKGROUND_KEEP_ALIVE_AUDIO_PLAYBACK ?
      [BACKGROUND_KEEP_ALIVE_AUDIO_PLAYBACK] : [BACKGROUND_KEEP_ALIVE_DATA_TRANSFER]
    try {
      if (this.lastKeepAliveMode === BACKGROUND_KEEP_ALIVE_AUDIO_PLAYBACK) {
        this.audioKeepAliveService.start()
      }
      const wantAgentObj = await wantAgent.getWantAgent(wantAgentInfo)
      const res = await backgroundTaskManager.startBackgroundRunning(this.context, modes, wantAgentObj)
      if (this.stoppingContinuousTask || generation !== this.runtimeGeneration) {
        await this.stopBackgroundTask(res.continuousTaskId)
        return
      }
      this.activeContinuousTaskId = res.continuousTaskId
      this.hasActiveContinuousTask = true
      this.setNotificationId(res.notificationId)
      publishTextNotification(this.lastTaskName)
      Logger.info(`continuous task recovered id=${res.continuousTaskId ?? -1}`, this.logTarget)
    } catch (error) {
      const err = error as BusinessError
      Logger.error(`continuous task recovery failed: ${err.code}, ${err.message}`, this.logTarget)
      this.onBackgroundTaskSuspended(`${err.code}`)
    } finally {
      this.continuousTaskRecoveryInFlight = false
    }
  }

  private async handleBackgroundRunningStarted(res: backgroundTaskManager.ContinuousTaskNotification, cfg: string,
    uuid: string | undefined, name: string | undefined, generation: number): Promise<boolean> {
    if (generation !== this.runtimeGeneration) {
      return false
    }
    if (this.runNetworkInstance(cfg)) {
      startRuntimeStatsRecording(this.context.filesDir)
      try {
        const config: ConfigJson = JSON.parse(cfg)
        if (config.no_tun) {
          this.activateMissionContinue()
        }
      } catch (_) {
      }
      setTimeout(() => {
        if (generation !== this.runtimeGeneration) {
          return
        }
        this.refreshFavoriteCard()
        this.setNotificationId(res.notificationId)
        publishTextNotification(name ?? "N/A")
      }, 300)
      if (uuid) {
        HMRouterMgr.to('StatusPage')
          .withParam(uuid)
          .withAnimator(new BottomAnimator())
          .pushAsync()
      }
      return true
    } else {
      sendToast("实例启动失败, 可能是内核错误, 请上报日志.", $r("sys.symbol.exclamationmark_circle"), 1)
      Logger.error("启动失败", this.logTarget)
      await this.stopContinuousTask()
      return false
    }
  }

  async stopContinuousTask(): Promise<void> {
    this.runtimeGeneration++
    this.stoppingContinuousTask = true
    this.deactivateMissionContinue()
    this.audioKeepAliveService.stop()
    let stopError: Error | undefined = undefined
    const taskId = this.activeContinuousTaskId
    const shouldStopBackgroundTask = this.shouldUseBackgroundKeepAlive() &&
      canIUse(CONTINUOUS_BACKGROUND_TASK_SYSCAP) && this.hasActiveContinuousTask
    if (shouldStopBackgroundTask) {
      Logger.info(`stop background alive id=${taskId ?? -1}`, this.logTarget)
      try {
        await this.stopBackgroundTask(taskId)
        this.hasActiveContinuousTask = false
        this.activeContinuousTaskId = undefined
      } catch (error) {
        const err = error as BusinessError
        stopError = err
        Logger.error(`stopBackgroundRunning failed: ${err.code}, ${err.message}`, this.logTarget)
      }
    }
    try {
      await this.destroyVpnConnection()
    } catch (error) {
      const vpnError = error as Error
      if (!stopError) {
        stopError = vpnError
      }
    } finally {
      this.stoppingContinuousTask = false
    }
    if (stopError) {
      throw stopError
    }
    this.clearNotificationId()
    stopRuntimeStatsRecording()
  }
}
