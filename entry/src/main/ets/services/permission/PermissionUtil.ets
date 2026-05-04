import { abilityAccessCtrl, bundleManager, Permissions } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { vpnExtension } from '@kit.NetworkKit';
import { AppManager } from '../../AppManager';
import { Logger, LogLocate } from '../../shared/logging/Logger';
import { notificationManager } from '@kit.NotificationKit';
import { common } from '@kit.AbilityKit';

const permissions: Array<Permissions> =
  ['ohos.permission.APPROXIMATELY_LOCATION', 'ohos.permission.DISTRIBUTED_DATASYNC'];

@LogLocate("PermissionUtil")
@ObservedV2
export class PermissionUtil {
  @Trace distributePerm: abilityAccessCtrl.GrantStatus = abilityAccessCtrl.GrantStatus.PERMISSION_DENIED
  @Trace locPerm: abilityAccessCtrl.GrantStatus = abilityAccessCtrl.GrantStatus.PERMISSION_DENIED
  @Trace notificationPerm: abilityAccessCtrl.GrantStatus = abilityAccessCtrl.GrantStatus.PERMISSION_DENIED

  updateDistributePerm(status: number) {
    if (status === 2) {
      Logger.error("invalid request of DistributePerm", this)
    } else {
      Logger.info("update DistributePerm: " + status, this)
      this.distributePerm = status
    }
  }

  updateLocPerm(status: number) {
    if (status === 2) {
      Logger.error("invalid request of LocPerm", this)
    } else {
      Logger.info("update LocPerm: " + status, this)
      this.locPerm = status
    }
  }

  updateNotificationPerm(status: number) {
    if (status === 2) {
      Logger.error("invalid request of LocPerm", this)
    } else {
      Logger.info("update NotificationPerm: " + status, this)
      this.notificationPerm = status
    }
  }

  async checkPermissionGrant(permission: Permissions): Promise<abilityAccessCtrl.GrantStatus> {
    let atManager: abilityAccessCtrl.AtManager = abilityAccessCtrl.createAtManager();
    let grantStatus: abilityAccessCtrl.GrantStatus = abilityAccessCtrl.GrantStatus.PERMISSION_DENIED;
    let tokenId: number = 0;
    try {
      let bundleInfo: bundleManager.BundleInfo =
        await bundleManager.getBundleInfoForSelf(bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION);
      let appInfo: bundleManager.ApplicationInfo = bundleInfo.appInfo;
      tokenId = appInfo.accessTokenId;
    } catch (error) {
      const err: BusinessError = error as BusinessError;
      Logger.error(`Failed to get bundle info for self. Code is ${err.code}, message is ${err.message}`,
        this);
    }
    try {
      grantStatus = await atManager.checkAccessToken(tokenId, permission);
    } catch (error) {
      const err: BusinessError = error as BusinessError;
      Logger.error(`Failed to check access token. Code is ${err.code}, message is ${err.message}`, this);
    }
    return grantStatus;
  }

  async updatePermStatus(): Promise<void> {
    let status = await this.checkPermissionGrant(permissions[0])
    let status1 = await this.checkPermissionGrant(permissions[1])
    this.updateLocPerm(status)
    this.updateDistributePerm(status1)
    try {
      this.updateNotificationPerm(notificationManager.isNotificationEnabledSync() ? 0 : -1)
    } catch (error) {
      this.updateNotificationPerm(-1)
    }
  }

  async requestLocPerm(): Promise<boolean> {
    let atManager: abilityAccessCtrl.AtManager = abilityAccessCtrl.createAtManager();
    let status = await this.checkPermissionGrant(permissions[0])
    if (status == abilityAccessCtrl.GrantStatus.PERMISSION_DENIED) {
      try {
        let result = await atManager.requestPermissionsFromUser(AppManager.content.context!,
          ['ohos.permission.APPROXIMATELY_LOCATION'])
        if (!result.dialogShownResults![0]) {
          return this.requestLocPermFromSetting()
        } else {
          this.updateLocPerm(result.authResults[0])
          return Promise.resolve(result.authResults[0] === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED)
        }
      } catch (error) {
        Logger.error(`requestLocPerm error: ${JSON.stringify(error)}`, this)
        return Promise.resolve(false)
      }
    } else {
      return Promise.resolve(true)
    }
  }

  async requestDistributePerm(again: boolean = true): Promise<boolean> {
    let atManager: abilityAccessCtrl.AtManager = abilityAccessCtrl.createAtManager();
    let status = await this.checkPermissionGrant(permissions[1])
    if (status !== abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED) {
      try {
        let result = await atManager.requestPermissionsFromUser(AppManager.content.context!,
          ['ohos.permission.DISTRIBUTED_DATASYNC'])
        if (!result.dialogShownResults![0] && again) {
          return this.requestDistributePermFromSetting()
        } else {
          this.updateDistributePerm(result.authResults[0])
          return Promise.resolve(result.authResults[0] === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED)
        }
      } catch (error) {
        Logger.error(`requestDistributePerm error: ${JSON.stringify(error)}`, this)
        return Promise.resolve(false)
      }
    } else {
      return Promise.resolve(true)
    }
  }

  async requestNotificationPerm(again: boolean = true): Promise<boolean> {
    let context = AppManager.content.uiContext!.getHostContext() as common.UIAbilityContext
    return new Promise<boolean>((resolve) => {
      try {
        let enabled: boolean = notificationManager.isNotificationEnabledSync();
        if (!enabled) {
          notificationManager.requestEnableNotification(context).then(() => {
            this.updateNotificationPerm(0)
            resolve(true)
          }).catch((err: BusinessError) => {
            if (err.code == 1600004 && again) {
              notificationManager.openNotificationSettings(context).then(() => {
                let enabled = notificationManager.isNotificationEnabledSync()
                this.updateNotificationPerm(enabled?0:-1)
                resolve(enabled)
              }).catch(() => {});
            }else {
              this.updateNotificationPerm(-1)
              resolve(false)
            }
          });
        }else {
          this.updateNotificationPerm(0)
          resolve(true)
        }
      } catch (_) {}
    })
  }

  async requestLocPermFromSetting(): Promise<boolean> {
    if (AppManager.permission.isGetLocPerm()) {
      Logger.debug("LocPerm request again", this)
      let atManager: abilityAccessCtrl.AtManager = abilityAccessCtrl.createAtManager();
      try {
        let rst = await atManager.requestPermissionOnSetting(AppManager.content.context!,
          ["ohos.permission.APPROXIMATELY_LOCATION"])
        this.updateLocPerm(rst[0])
        return Promise.resolve(rst[0] === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED)
      } catch (error) {
        Logger.error(`requestLocPermFromSetting error: ${JSON.stringify(error)}`, this)
        return Promise.resolve(false)
      }
    } else {
      return Promise.resolve(true)
    }
  }

  async requestDistributePermFromSetting(): Promise<boolean> {
    if (AppManager.permission.isGetDistributePerm()) {
      Logger.debug("DistributePerm request again", this)
      let atManager: abilityAccessCtrl.AtManager = abilityAccessCtrl.createAtManager();
      try {
        let rst =
          await atManager.requestPermissionOnSetting(AppManager.content.context!, ["ohos.permission.DISTRIBUTED_DATASYNC"])
        this.updateDistributePerm(rst[0])
        return Promise.resolve(rst[0] === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED)
      } catch (error) {
        Logger.error(`requestDistributePermFromSetting error: ${JSON.stringify(error)}`, this)
        return Promise.resolve(false)
      }
    } else {
      return Promise.resolve(true)
    }
  }

  isGetDistributePerm(): boolean {
    return this.distributePerm == abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED
  }

  isGetLocPerm(): boolean {
    return this.locPerm == abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED
  }

  isGetNotificationPerm(): boolean {
    return this.notificationPerm == abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED
  }

  requestVpnPerm(callback: () => void, finallyCallback: () => void = () => {}) {
    vpnExtension.startVpnExtensionAbility({
      deviceId: '',
      bundleName: 'top.frankhan.easytier',
      abilityName: 'EasyTierAbility',
    }).then(() => {
      Logger.debug("startVpnExtensionAbility", this)
      vpnExtension.stopVpnExtensionAbility({
        deviceId: '',
        bundleName: 'top.frankhan.easytier',
        abilityName: 'EasyTierAbility',
      }).then(callback)
    }).finally(() => {
      finallyCallback()
    })
  }
}
