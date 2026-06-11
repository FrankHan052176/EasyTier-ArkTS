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
import { startRuntimeStatsRecording, stopRuntimeStatsRecording } from './RuntimeStatsService'

export interface EntryBackgroundTaskServiceOptions {
  context: common.UIAbilityContext
  logTarget: Object | string
  runNetworkInstance: (cfg: string) => boolean
  activateMissionContinue: () => void
  deactivateMissionContinue: () => void
  refreshFavoriteCard: () => void
  setNotificationId: (notificationId: number) => void
  destroyVpnConnection: () => Promise<void>
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

  constructor(options: EntryBackgroundTaskServiceOptions) {
    this.context = options.context
    this.logTarget = options.logTarget
    this.runNetworkInstance = options.runNetworkInstance
    this.activateMissionContinue = options.activateMissionContinue
    this.deactivateMissionContinue = options.deactivateMissionContinue
    this.refreshFavoriteCard = options.refreshFavoriteCard
    this.setNotificationId = options.setNotificationId
    this.destroyVpnConnection = options.destroyVpnConnection
  }

  startContinuousTask(cfg: string, uuid: string | undefined, name: string | undefined): void {
    if (!canIUse("SystemCapability.ResourceSchedule.BackgroundTaskManager.ContinuousTask")) {
      if (!this.runNetworkInstance(cfg)) {
        sendToast("实例启动失败, 可能是内核错误, 请上报日志.", $r("sys.symbol.exclamationmark_circle"), 1)
        Logger.error("启动失败", this.logTarget)
      } else {
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
    Logger.info("start background alive", this.logTarget)
    const wantAgentInfo: wantAgent.WantAgentInfo = {
      wants: [
        {
          bundleName: "top.frankhan.easytier",
          abilityName: "EntryAbility"
        }
      ],
      actionType: wantAgent.OperationType.START_ABILITY,
      requestCode: 0,
      actionFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
    }
    try {
      wantAgent.getWantAgent(wantAgentInfo).then((wantAgentObj: WantAgent) => {
        try {
          backgroundTaskManager.startBackgroundRunning(this.context, ["dataTransfer"], wantAgentObj).then((res: backgroundTaskManager.ContinuousTaskNotification) => {
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
          }).catch((err: BusinessError) => {
            Logger.error(`startBackgroundRunning failed: ${err.code}, ${err.message}`, this.logTarget)
          })
        } catch (error) {
          Logger.error(`startBackgroundRunning error: ${JSON.stringify(error)}`, this.logTarget)
        }
      }).catch((err: BusinessError) => {
        Logger.error(`getWantAgent failed: ${err.code}, ${err.message}`, this.logTarget)
      })
    } catch (error) {
      Logger.error(`getWantAgent error: ${JSON.stringify(error)}`, this.logTarget)
    }
  }

  async stopContinuousTask(): Promise<void> {
    this.deactivateMissionContinue()
    stopRuntimeStatsRecording()
    if (!canIUse("SystemCapability.ResourceSchedule.BackgroundTaskManager.ContinuousTask")) {
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
