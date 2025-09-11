import { abilityAccessCtrl, bundleManager, common, Permissions } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { vpnExtension } from '@kit.NetworkKit';
import Logger from './Logger';

const permissions: Array<Permissions> =
  ['ohos.permission.APPROXIMATELY_LOCATION', 'ohos.permission.DISTRIBUTED_DATASYNC'];
let permResult: abilityAccessCtrl.GrantStatus[] = [abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED, abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED]

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

export async function checkPerm(context: common.UIAbilityContext) {
  let atManager: abilityAccessCtrl.AtManager = abilityAccessCtrl.createAtManager();
  let status = await checkPermissionGrant(permissions[0])
  let status1 = await checkPermissionGrant(permissions[1])
  if (status !== abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED ||
    status1 !== abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED) {
    atManager.requestPermissionsFromUser(context, permissions).then((result) => {
      permResult = result.authResults
    })
  }
}

export async function checkLocPerm(context: common.UIAbilityContext): Promise<boolean> {
  if (permResult[0] != abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED) {
    Logger.debug("0 未授权")
    let atManager: abilityAccessCtrl.AtManager = abilityAccessCtrl.createAtManager();
    let rst = await atManager.requestPermissionOnSetting(context, ["ohos.permission.APPROXIMATELY_LOCATION"])
    permResult[0] = rst[0]
    return Promise.resolve(rst[0] === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED)
  }else {
    return Promise.resolve(true)
  }
}

export async function checkDistributePerm(context: common.UIAbilityContext): Promise<boolean> {
  if (permResult[1] != abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED) {
    Logger.debug("1 未授权")
    let atManager: abilityAccessCtrl.AtManager = abilityAccessCtrl.createAtManager();
    let rst = await atManager.requestPermissionOnSetting(context, ["ohos.permission.DISTRIBUTED_DATASYNC"])
    permResult[1] = rst[0]
    return Promise.resolve(rst[0] === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED)
  }else {
    return Promise.resolve(true)
  }
}

export function isGetDistributePerm(): boolean {
  return permResult[1] == abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED
}

export function requestVpnPerm(callback: () => void) {
  vpnExtension.startVpnExtensionAbility({
    deviceId: '',
    bundleName: 'top.frankhan.et4hm',
    abilityName: 'VpnAbility',
  }).then(() => {
    vpnExtension.stopVpnExtensionAbility({
      deviceId: '',
      bundleName: 'top.frankhan.et4hm',
      abilityName: 'VpnAbility',
    }).then(callback)
  }).finally(() => {
    //TODO 检测tun是否成功启动，否则发出警告
  })
}
