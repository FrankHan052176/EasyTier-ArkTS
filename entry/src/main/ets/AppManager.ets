import { ContextUtil } from './ContextUtil';
import { DataUtil } from './DataUtil';
import { EasyTierUtil } from './EasyTierUtil';
import { LogLocate } from './util/Logger';
import { distributedKVStore } from '@kit.ArkData';
import { PermissionUtil } from './PermissionUtil';
import { PreferenceUtil } from './PreferencesUtil';
import { WebUtil } from './WebUtil';
import { UIState } from './class/UIState';

@LogLocate("AppManager")
export class AppManager {
  public static KVManager: distributedKVStore.KVManager | undefined
  public static data: DataUtil = new DataUtil()
  public static content: ContextUtil = new ContextUtil()
  public static easytier: EasyTierUtil = new EasyTierUtil()
  public static permission: PermissionUtil = new PermissionUtil()
  public static preference: PreferenceUtil = new PreferenceUtil()
  public static web: WebUtil = new WebUtil()
  public static uiState: UIState = new UIState()

  static async init(uiContext: UIContext) {
    AppManager.content.init(uiContext)
    AppManager.permission.updatePermStatus()
    await AppManager.preference.init(AppManager.content.context!)
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