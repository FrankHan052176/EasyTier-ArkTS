import { abilityAccessCtrl, bundleManager, Permissions } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { vpnExtension } from '@kit.NetworkKit';
import { AppManager } from '../../AppManager';
import { Logger, LogLocate } from '../../shared/logging/Logger';
import { APP_BUNDLE_NAME, VPN_EXTENSION_ABILITY_NAME } from '../runtime/AbilityRuntimePolicy';

const DISTRIBUTED_DATASYNC_PERMISSION: Permissions = 'ohos.permission.DISTRIBUTED_DATASYNC';
let vpnPermissionReady: boolean = false

@LogLocate("PermissionUtil")
@ObservedV2
export class PermissionUtil {
  @Trace distributePerm: abilityAccessCtrl.GrantStatus = abilityAccessCtrl.GrantStatus.PERMISSION_DENIED

  updateDistributePerm(status: number) {
    if (status === 2) {
      Logger.error("invalid request of DistributePerm", this)
    } else {
      Logger.info("update DistributePerm: " + status, this)
      this.distributePerm = status
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
    let status = await this.checkPermissionGrant(DISTRIBUTED_DATASYNC_PERMISSION)
    this.updateDistributePerm(status)
  }

  async requestDistributePerm(again: boolean = true): Promise<boolean> {
    let atManager: abilityAccessCtrl.AtManager = abilityAccessCtrl.createAtManager();
    let status = await this.checkPermissionGrant(DISTRIBUTED_DATASYNC_PERMISSION)
    if (status !== abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED) {
      try {
        let result = await atManager.requestPermissionsFromUser(AppManager.content.context!,
          [DISTRIBUTED_DATASYNC_PERMISSION])
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

  async requestDistributePermFromSetting(): Promise<boolean> {
    if (AppManager.permission.isGetDistributePerm()) {
      Logger.debug("DistributePerm request again", this)
      let atManager: abilityAccessCtrl.AtManager = abilityAccessCtrl.createAtManager();
      try {
        let rst =
          await atManager.requestPermissionOnSetting(AppManager.content.context!, [DISTRIBUTED_DATASYNC_PERMISSION])
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

  requestVpnPerm(callback: () => void, finallyCallback: () => void = () => {},
    errorCallback: (error: BusinessError) => void = () => {}) {
    if (vpnPermissionReady) {
      callback()
      finallyCallback()
      return
    }
    vpnExtension.startVpnExtensionAbility({
      deviceId: '',
      bundleName: APP_BUNDLE_NAME,
      abilityName: VPN_EXTENSION_ABILITY_NAME,
    }).then(() => {
      Logger.debug("startVpnExtensionAbility", this)
      return vpnExtension.stopVpnExtensionAbility({
        deviceId: '',
        bundleName: APP_BUNDLE_NAME,
        abilityName: VPN_EXTENSION_ABILITY_NAME,
      }).then(() => {
        vpnPermissionReady = true
        callback()
      })
    }).catch((error: BusinessError) => {
      Logger.error(`VPN permission probe failed: ${error.code}, ${error.message}`, this)
      errorCallback(error)
    }).finally(() => {
      finallyCallback()
    })
  }
}
