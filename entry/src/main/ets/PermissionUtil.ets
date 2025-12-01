import { abilityAccessCtrl, bundleManager, Permissions } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { vpnExtension } from '@kit.NetworkKit';
import { AppManager } from './AppManager';
import Manager from './Manager';
import { Logger, LogLocate } from './util/Logger';

const permissions: Array<Permissions> =
  ['ohos.permission.APPROXIMATELY_LOCATION', 'ohos.permission.DISTRIBUTED_DATASYNC'];

@LogLocate("PermissionUtil")
@ObservedV2
export class PermissionUtil {
  @Trace distributePerm: abilityAccessCtrl.GrantStatus = abilityAccessCtrl.GrantStatus.PERMISSION_DENIED
  @Trace locPerm: abilityAccessCtrl.GrantStatus = abilityAccessCtrl.GrantStatus.PERMISSION_DENIED
  updateDistributePerm(status: number) {
    if (status === 2) {
      Logger.error("invalid request of DistributePerm", PermissionUtil)
    }else {
      Logger.info("update DistributePerm: "+status, PermissionUtil)
      this.distributePerm = status
    }
  }
  updateLocPerm(status: number) {
    if (status === 2) {
      Logger.error("invalid request of LocPerm", PermissionUtil)
    }else {
      Logger.info("update LocPerm: "+status, PermissionUtil)
      this.locPerm = status
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
      Logger.error(`Failed to get bundle info for self. Code is ${err.code}, message is ${err.message}`, PermissionUtil);
    }
    try {
      grantStatus = await atManager.checkAccessToken(tokenId, permission);
    } catch (error) {
      const err: BusinessError = error as BusinessError;
      Logger.error(`Failed to check access token. Code is ${err.code}, message is ${err.message}`, PermissionUtil);
    }
    return grantStatus;
  }

  async updatePermStatus(): Promise<void> {
    let status = await this.checkPermissionGrant(permissions[0])
    let status1 = await this.checkPermissionGrant(permissions[1])
    this.updateLocPerm(status)
    this.updateDistributePerm(status1)
  }

  async requestLocPerm(): Promise<boolean> {
    let atManager: abilityAccessCtrl.AtManager = abilityAccessCtrl.createAtManager();
    let status = await this.checkPermissionGrant(permissions[0])
    if (status == abilityAccessCtrl.GrantStatus.PERMISSION_DENIED) {
      let result = await atManager.requestPermissionsFromUser(AppManager.content.context!, ['ohos.permission.APPROXIMATELY_LOCATION'])
      if (!result.dialogShownResults![0]) {
        return this.requestLocPermFromSetting()
      }else {
        this.updateLocPerm(result.authResults[0])
        return Promise.resolve(result.authResults[0] === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED)
      }
    }else {
      return Promise.resolve(true)
    }
  }

  async requestDistributePerm(again: boolean = true): Promise<boolean> {
    let atManager: abilityAccessCtrl.AtManager = abilityAccessCtrl.createAtManager();
    let status = await this.checkPermissionGrant(permissions[1])
    if (status !== abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED) {
      let result = await atManager.requestPermissionsFromUser(AppManager.content.context!, ['ohos.permission.DISTRIBUTED_DATASYNC'])
      if (!result.dialogShownResults![0] && again) {
        return this.requestDistributePermFromSetting()
      }else {
        this.updateDistributePerm(result.authResults[0])
        return Promise.resolve(result.authResults[0] === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED)
      }
    }else {
      return Promise.resolve(true)
    }
  }

  async requestLocPermFromSetting(): Promise<boolean> {
    if (Manager.locPerm != abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED) {
      Logger.debug("[Permission] LocPerm request again", PermissionUtil)
      let atManager: abilityAccessCtrl.AtManager = abilityAccessCtrl.createAtManager();
      let rst = await atManager.requestPermissionOnSetting(AppManager.content.context, ["ohos.permission.APPROXIMATELY_LOCATION"])
      this.updateLocPerm(rst[0])
      return Promise.resolve(rst[0] === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED)
    }else {
      return Promise.resolve(true)
    }
  }

  async requestDistributePermFromSetting(): Promise<boolean> {
    if (Manager.distributePerm != abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED) {
      Logger.debug("[Permission] DistributePerm request again", PermissionUtil)
      let atManager: abilityAccessCtrl.AtManager = abilityAccessCtrl.createAtManager();
      let rst = await atManager.requestPermissionOnSetting(AppManager.content.context, ["ohos.permission.DISTRIBUTED_DATASYNC"])
      this.updateDistributePerm(rst[0])
      return Promise.resolve(rst[0] === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED)
    }else {
      return Promise.resolve(true)
    }
  }

  isGetDistributePerm(): boolean {
    return this.distributePerm == abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED
  }

  isGetLocPerm(): boolean {
    return this.locPerm == abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED
  }

  requestVpnPerm(callback: () => void, finallyCallback: () => void = () => {}) {
    vpnExtension.startVpnExtensionAbility({
      deviceId: '',
      bundleName: 'top.frankhan.easytier',
      abilityName: 'EasyTierAbility',
    }).then(() => {
      Logger.debug("[Permission] startVpnExtensionAbility")
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
