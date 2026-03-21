 import { notificationManager } from '@kit.NotificationKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { Logger } from './Logger';
import { InstanceInfo } from '../class/InstanceInfo';
import { AppManager } from '../AppManager';

export function publishTextNotification(instance_name: string): void {
  AppManager.permission.requestNotificationPerm(false).then(async (data) => {
    if (!data) {
      Logger.error(`未授予通知权限`, "NoticeHelper")
      return
    }
    if (AppManager.uiState.notificationId == undefined) {
      AppManager.uiState.notificationId = Date.now()
    }
    const request: notificationManager.NotificationRequest = {
      id: AppManager.uiState.notificationId ?? -1,
      content: {
        notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
        normal: {
          title: "已启动实例 "+instance_name,
          text: `0/s ↑ 0/s ↓`,
          additionalText: ''
        }
      }
    };
    notificationManager.publish(request, (err: BusinessError) => {
      if (err) {
        Logger.error(`通知发出失败, code: ${err.code}, message:${err.message}`, "NoticeHelper")
        return;
      }
    });
  })
}

export async function updateTextNotification(instance_name: string, instanceInfo: InstanceInfo): Promise<void> {
  if (AppManager.uiState.notificationId == undefined) {
    return
  }
  const updateRequest: notificationManager.NotificationRequest = {
    id: AppManager.uiState.notificationId ?? -1,
    content: {
      notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
      normal: {
        title: "已启动实例 "+instance_name,
        text: `${instanceInfo.getUploadRate().toFixed(1)}${instanceInfo.getUploadRateUnit()} ↑ ${instanceInfo.getDownloadRate().toFixed(1)}${instanceInfo.getDownloadRateUnit()} ↓`,
        additionalText: ''
      }
    },
    updateOnly: true,
  };
  notificationManager.publish(updateRequest, (err: BusinessError) => {
    if (err) {
      Logger.error(`通知更新失败, code: ${err.code}, message:${err.message}`, "NoticeHelper")
      return;
    }
  });
}

export async function cancelNotification(): Promise<void> {
  try {
    notificationManager.cancel(AppManager.uiState.notificationId ?? -1).catch(() => {});
    AppManager.uiState.notificationId = undefined
  } catch (_) {}
}