import { WantAgent, common, wantAgent } from '@kit.AbilityKit'
import { backgroundTaskManager } from '@kit.BackgroundTasksKit'
import { JSON } from '@kit.ArkTS'
import { BusinessError } from '@kit.BasicServicesKit'
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
  destroyVpnConnection: () => Promise<void>
  getBackgroundKeepAliveMode: () => string
  shouldUseBackgroundKeepAlive: () => boolean
}

export class EntryBackgroundTaskService {
  private readonly context: common.UIAbilityContext
  private readonly logTarget: Object | string
  private readonly runNetworkInstance: (cfg: string) => boolean
  private readonly activateMissionContinue: () => void
  private readonly deactivateMissionContinue: () => void
  private readonly refreshFavoriteCard: () => void
  private readonly setNotificationId: (notificationId: number) => void
  private readonly destroyVpnConnection: () => Promise<void>
  private readonly getBackgroundKeepAliveMode: () => string
  private readonly shouldUseBackgroundKeepAlive: () => boolean
  private readonly audioKeepAliveService: AudioKeepAliveService

  constructor(options: EntryBackgroundTaskServiceOptions) {
    this.context = options.context
    this.logTarget = options.logTarget
    this.runNetworkInstance = options.runNetworkInstance
    this.activateMissionContinue = options.activateMissionContinue
    this.deactivateMissionContinue = options.deactivateMissionContinue
    this.refreshFavoriteCard = options.refreshFavoriteCard
    this.setNotificationId = options.setNotificationId
    this.destroyVpnConnection = options.destroyVpnConnection
    this.getBackgroundKeepAliveMode = options.getBackgroundKeepAliveMode
    this.shouldUseBackgroundKeepAlive = options.shouldUseBackgroundKeepAlive
    this.audioKeepAliveService = new AudioKeepAliveService(options.logTarget)
  }

  startContinuousTask(cfg: string, uuid: string | undefined, name: string | undefined): void {
    const keepAliveMode = normalizeBackgroundKeepAliveMode(this.getBackgroundKeepAliveMode())
    if (!this.shouldUseBackgroundKeepAlive()) {
      Logger.info('start runtime without background keep alive', this.logTarget)
      this.handleRuntimeStartWithoutBackground(cfg, uuid, name)
      return
    }
    if (!canIUse(CONTINUOUS_BACKGROUND_TASK_SYSCAP)) {
      if (!this.runNetworkInstance(cfg)) {
        sendToast("实例启动失败, 可能是内核错误, 请上报日志.", $r("sys.symbol.exclamationmark_circle"), 1)
        Logger.error("启动失败", this.logTarget)
      } else {
        if (keepAliveMode === BACKGROUND_KEEP_ALIVE_AUDIO_PLAYBACK) {
          this.audioKeepAliveService.start()
        }
        startRuntimeStatsRecording(this.context.filesDir)
        try {
          const config: ConfigJson = JSON.parse(cfg)
          if (config.no_tun) {
            this.activateMissionContinue()
          }
        } catch (_) {
        }
      }
      return
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
      wantAgent.getWantAgent(wantAgentInfo).then((wantAgentObj: WantAgent) => {
        this.startBackgroundRunning(wantAgentObj, cfg, uuid, name, keepAliveMode)
      }).catch((err: BusinessError) => {
        Logger.error(`getWantAgent failed: ${err.code}, ${err.message}`, this.logTarget)
      })
    } catch (error) {
      Logger.error(`getWantAgent error: ${JSON.stringify(error)}`, this.logTarget)
    }
  }

  private handleRuntimeStartWithoutBackground(cfg: string, uuid: string | undefined, name: string | undefined): void {
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
        this.refreshFavoriteCard()
      }, 300)
      if (uuid) {
        HMRouterMgr.to('StatusPage')
          .withParam(uuid)
          .withAnimator(new BottomAnimator())
          .pushAsync()
      }
    } else {
      sendToast("实例启动失败, 可能是内核错误, 请上报日志.", $r("sys.symbol.exclamationmark_circle"), 1)
      Logger.error("启动失败", this.logTarget)
      void this.stopContinuousTask()
    }
  }

  private startBackgroundRunning(wantAgentObj: WantAgent, cfg: string, uuid: string | undefined,
    name: string | undefined, keepAliveMode: BackgroundKeepAliveMode): void {
    const modes = keepAliveMode === BACKGROUND_KEEP_ALIVE_AUDIO_PLAYBACK ? [BACKGROUND_KEEP_ALIVE_AUDIO_PLAYBACK] :
      [BACKGROUND_KEEP_ALIVE_DATA_TRANSFER]
    try {
      backgroundTaskManager.startBackgroundRunning(this.context, modes, wantAgentObj).then((res: backgroundTaskManager.ContinuousTaskNotification) => {
        this.handleBackgroundRunningStarted(res, cfg, uuid, name)
      }).catch((err: BusinessError) => {
        this.audioKeepAliveService.stop()
        sendToast("后台保活启动失败，请尝试切换保活模式。", $r("sys.symbol.exclamationmark_circle"), 1)
        Logger.error(`startBackgroundRunning ${keepAliveMode} failed: ${err.code}, ${err.message}`, this.logTarget)
      })
    } catch (error) {
      this.audioKeepAliveService.stop()
      Logger.error(`startBackgroundRunning ${keepAliveMode} error: ${JSON.stringify(error)}`, this.logTarget)
    }
  }

  private handleBackgroundRunningStarted(res: backgroundTaskManager.ContinuousTaskNotification, cfg: string,
    uuid: string | undefined, name: string | undefined): void {
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
    } else {
      sendToast("实例启动失败, 可能是内核错误, 请上报日志.", $r("sys.symbol.exclamationmark_circle"), 1)
      Logger.error("启动失败", this.logTarget)
      this.stopContinuousTask()
    }
  }

  async stopContinuousTask(): Promise<void> {
    this.deactivateMissionContinue()
    this.audioKeepAliveService.stop()
    stopRuntimeStatsRecording()
    if (!this.shouldUseBackgroundKeepAlive()) {
      void this.destroyVpnConnection()
      return
    }
    if (!canIUse(CONTINUOUS_BACKGROUND_TASK_SYSCAP)) {
      return
    }
    Logger.info("stop background alive", this.logTarget)
    backgroundTaskManager.stopBackgroundRunning(this.context).catch((err: BusinessError) => {
      Logger.error(`stopBackgroundRunning failed: ${err.code}, ${err.message}`, this.logTarget)
    }).finally(() => {
      void this.destroyVpnConnection()
    })
  }
}
