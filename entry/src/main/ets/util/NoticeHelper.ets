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
}

export async function updateTextNotification(instance_name: string, instanceInfo: InstanceInfo): Promise<void> {
  if (!shouldUseLiveViewNotification() || AppManager.uiState.notificationId == undefined) {
    return
  }
  const text = `${instanceInfo.getUploadRate().toFixed(1)}${instanceInfo.getUploadRateUnit()} ↑ ${instanceInfo.getDownloadRate().toFixed(1)}${instanceInfo.getDownloadRateUnit()} ↓`
  const progressValue = Math.min(100, Math.max(0, (instanceInfo.getUploadRate() / (instanceInfo.getUploadRate() + 10)) * 100))
  const updateRequest = buildLiveViewRequest(instance_name, text, progressValue)
  notificationManager.publish(updateRequest, (err: BusinessError) => {
    if (err) {
      Logger.error(`实况窗通知更新失败, nid: ${AppManager.uiState.notificationId}, code: ${err.code}, message:${err.message}`, "NoticeHelper")
    }
  })
}
