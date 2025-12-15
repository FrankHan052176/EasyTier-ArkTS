import { ContentUtil } from './ContentUtil';
import { ContextUtil } from './ContextUtil';
import { DataUtil } from './DataUtil';
import { EasyTierUtil } from './EasyTierUtil';
import { Logger, LogLocate } from './util/Logger';
import { distributedKVStore, preferences } from '@kit.ArkData';
import { PermissionUtil } from './PermissionUtil';
import { PreferenceUtil } from './PreferencesUtil';
import { LayoutUtil } from './LayoutUtil';
import { WebUtil } from './WebUtil';
import { deviceInfo } from '@kit.BasicServicesKit';

@LogLocate("AppManager")
export class AppManager {
  public static KVManager: distributedKVStore.KVManager | undefined
  public static data: DataUtil = new DataUtil()
  public static content: ContextUtil = new ContextUtil()
  public static easytier: EasyTierUtil = new EasyTierUtil()
  public static permission: PermissionUtil = new PermissionUtil()
  public static preference: PreferenceUtil = new PreferenceUtil()
  public static layout: LayoutUtil = new LayoutUtil()
  public static web: WebUtil = new WebUtil()

  static init(uiContext: UIContext) {
    ContentUtil.initConfigFields()
    AppManager.content.init(uiContext)
    if (deviceInfo.productModel !== "emulator") {
      AppManager.easytier.init()
    }
    AppManager.permission.updatePermStatus()
    "".replace(".","")
    try {
      AppManager.preference.init(preferences.getPreferencesSync(AppManager.content.context,
        { name: 'EasyTierPreferences' }))
    } catch (error) {
      Logger.error(`PreferenceUtil failed to init.\n${error}`, AppManager)
    }
    AppManager.data.init()
  }
}

export function Spx2vp(px: number): number {
  if (AppManager.content.uiContext) {
    return AppManager.content.uiContext.px2vp(px)
  } else {
    return px2vp(px)
  }
}

export function Spx2fp(px: number): number {
  if (AppManager.content.uiContext) {
    return AppManager.content.uiContext.px2fp(px)
  } else {
    return px2fp(px)
  }
}

export function Svp2px(px: number): number {
  if (AppManager.content.uiContext) {
    return AppManager.content.uiContext.vp2px(px)
  } else {
    return vp2px(px)
  }
}

export function Sfp2px(px: number): number {
  if (AppManager.content.uiContext) {
    return AppManager.content.uiContext.fp2px(px)
  } else {
    return fp2px(px)
  }
}

export function Sfp2vp(fp: number): number {
  return Spx2vp(Sfp2px(fp))
}

export function Svp2fp(vp: number): number {
  return Spx2fp(Svp2px(vp))
}