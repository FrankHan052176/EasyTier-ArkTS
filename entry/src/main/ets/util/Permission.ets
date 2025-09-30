import { abilityAccessCtrl, bundleManager, common, Permissions } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { vpnExtension } from '@kit.NetworkKit';
import Manager from '../Manager';
import Logger from './Logger';

const permissions: Array<Permissions> =
  ['ohos.permission.APPROXIMATELY_LOCATION', 'ohos.permission.DISTRIBUTED_DATASYNC'];

async function checkPermissionGrant(permission: Permissions): Promise<abilityAccessCtrl.GrantStatus> {
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
    Logger.error(`Failed to get bundle info for self. Code is ${err.code}, message is ${err.message}`);
  }
  try {
    grantStatus = await atManager.checkAccessToken(tokenId, permission);
  } catch (error) {
    const err: BusinessError = error as BusinessError;
    Logger.error(`Failed to check access token. Code is ${err.code}, message is ${err.message}`);
  }
  return grantStatus;
}

export async function updatePermStatus(): Promise<void> {
  let status = await checkPermissionGrant(permissions[0])
  let status1 = await checkPermissionGrant(permissions[1])
  Manager.updateLocPerm(status)
  Manager.updateDistributePerm(status1)
}

export async function requestLocPerm(context: Context): Promise<boolean> {
  let atManager: abilityAccessCtrl.AtManager = abilityAccessCtrl.createAtManager();
  let status = await checkPermissionGrant(permissions[0])
  if (status == abilityAccessCtrl.GrantStatus.PERMISSION_DENIED) {
    let result = await atManager.requestPermissionsFromUser(context, ['ohos.permission.APPROXIMATELY_LOCATION'])
    if (!result.dialogShownResults![0]) {
      return requestLocPermFromSetting(context)
    }else {
      Manager.updateLocPerm(result.authResults[0])
      return Promise.resolve(result.authResults[0] === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED)
    }
  }else {
    return Promise.resolve(true)
  }
}

export async function requestDistributePerm(context: Context, again: boolean = true): Promise<boolean> {
  let atManager: abilityAccessCtrl.AtManager = abilityAccessCtrl.createAtManager();
  let status = await checkPermissionGrant(permissions[1])
  if (status !== abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED) {
    let result = await atManager.requestPermissionsFromUser(context, ['ohos.permission.DISTRIBUTED_DATASYNC'])
    if (!result.dialogShownResults![0] && again) {
      return requestDistributePermFromSetting(context)
    }else {
      Manager.updateDistributePerm(result.authResults[0])
      return Promise.resolve(result.authResults[0] === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED)
    }
  }else {
    return Promise.resolve(true)
  }
}

export async function requestLocPermFromSetting(context: Context): Promise<boolean> {
  if (Manager.locPerm != abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED) {
    Logger.debug("[Permission] LocPerm request again")
    let atManager: abilityAccessCtrl.AtManager = abilityAccessCtrl.createAtManager();
    let rst = await atManager.requestPermissionOnSetting(context, ["ohos.permission.APPROXIMATELY_LOCATION"])
    Manager.updateLocPerm(rst[0])
    return Promise.resolve(rst[0] === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED)
  }else {
    return Promise.resolve(true)
  }
}

export async function requestDistributePermFromSetting(context: Context): Promise<boolean> {
  if (Manager.distributePerm != abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED) {
    Logger.debug("[Permission] DistributePerm request again")
    let atManager: abilityAccessCtrl.AtManager = abilityAccessCtrl.createAtManager();
    let rst = await atManager.requestPermissionOnSetting(context, ["ohos.permission.DISTRIBUTED_DATASYNC"])
    Manager.updateDistributePerm(rst[0])
    return Promise.resolve(rst[0] === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED)
  }else {
    return Promise.resolve(true)
  }
}

export function isGetDistributePerm(): boolean {
  return Manager.distributePerm == abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED
}

export function isGetLocPerm(): boolean {
  return Manager.locPerm == abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED
}

export function requestVpnPerm(callback: () => void, finallyCallback: () => void = () => {}) {
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
