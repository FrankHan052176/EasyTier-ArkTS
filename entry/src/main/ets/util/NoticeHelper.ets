import { notificationManager } from '@kit.NotificationKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { Logger } from '../shared/logging/Logger';
import { InstanceInfo } from '../class/InstanceInfo';
import { AppManager } from '../AppManager';
import {
  BACKGROUND_KEEP_ALIVE_DATA_TRANSFER,
  normalizeBackgroundKeepAliveMode
} from '../types/runtime/BackgroundKeepAliveTypes';
import { shouldUseEntryBackgroundKeepAlive } from '../services/runtime/AbilityRuntimePolicy';
import { LiveViewActivityProgress } from '../services/runtime/LiveViewActivityProgress';

const LIVE_VIEW_MIN_UPDATE_INTERVAL_MS = 5000
const LIVE_VIEW_UNCHANGED_HEARTBEAT_MS = 30000
let lastLiveViewSignature: string = ''
let lastLiveViewPublishedAt: number = 0
const liveViewActivityProgress = new LiveViewActivityProgress()

function shouldUseLiveViewNotification(): boolean {
  return shouldUseEntryBackgroundKeepAlive() && normalizeBackgroundKeepAliveMode(AppManager.uiState.background_keep_alive_mode) ===
    BACKGROUND_KEEP_ALIVE_DATA_TRANSFER
}

function buildLiveViewRequest(instanceName: string, text: string, progressValue: number): notificationManager.NotificationRequest {
  const downLoadTemplate: notificationManager.NotificationTemplate = {
    name: 'downloadTemplate',
    data: {
      title: "已启动实例 " + instanceName,
      fileName: text,
      progressValue
    }
  }
  return {
    content: {
      notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_SYSTEM_LIVE_VIEW,
      systemLiveView: {
        typeCode: 8,
        title: "已启动实例 " + instanceName,
        text,
      }
    },
    id: AppManager.uiState.notificationId ?? -1,
    notificationSlotType: notificationManager.SlotType.LIVE_VIEW,
    template: downLoadTemplate
  }
}

export function publishTextNotification(instance_name: string): void {
  if (!shouldUseLiveViewNotification()) {
    return
  }
  notificationManager.publish(buildLiveViewRequest(instance_name, `0 ↑ 0 ↓`, 0), (err: BusinessError) => {
    if (err) {
      Logger.error(`实况窗通知发布失败, nid: ${AppManager.uiState.notificationId}, code: ${err.code}, message:${err.message}`, "NoticeHelper")
    }
  })
  lastLiveViewSignature = ''
  lastLiveViewPublishedAt = Date.now()
  liveViewActivityProgress.reset()
}

export async function updateTextNotification(instance_name: string, instanceInfo: InstanceInfo): Promise<void> {
  if (!shouldUseLiveViewNotification() || AppManager.uiState.notificationId == undefined) {
    return
  }
  const now = Date.now()
  const elapsedMs = now - lastLiveViewPublishedAt
  if (elapsedMs < LIVE_VIEW_MIN_UPDATE_INTERVAL_MS) {
    return
  }
  const uploadRate = instanceInfo.getUploadRate()
  const downloadRate = instanceInfo.getDownloadRate()
  const text = `${uploadRate.toFixed(1)}${instanceInfo.getUploadRateUnit()} ↑ ${downloadRate.toFixed(1)}${instanceInfo.getDownloadRateUnit()} ↓`
  const progressValue = liveViewActivityProgress.advance()
  const signature = `${instance_name}:${text}:${progressValue}`
  if (signature === lastLiveViewSignature && elapsedMs < LIVE_VIEW_UNCHANGED_HEARTBEAT_MS) {
    return
  }
  lastLiveViewSignature = signature
  lastLiveViewPublishedAt = now
  const updateRequest = buildLiveViewRequest(instance_name, text, progressValue)
  notificationManager.publish(updateRequest, (err: BusinessError) => {
    if (err) {
      Logger.error(`实况窗通知更新失败, nid: ${AppManager.uiState.notificationId}, code: ${err.code}, message:${err.message}`, "NoticeHelper")
    }
  })
}
