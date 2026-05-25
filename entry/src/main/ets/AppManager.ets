import { ContextUtil } from './services/context/ContextUtil';
import { DataUtil } from './services/data/storage/DataUtil';
import { EasyTierUtil } from './EasyTierUtil';
import { LogLocate } from './shared/logging/Logger';
import { PermissionUtil } from './services/permission/PermissionUtil';
import { PreferenceUtil } from './services/preferences/storage/PreferencesUtil';
import { WebUtil } from './services/web/WebUtil';
import { UIState } from './store/ui/UIState';
import { CloudConfigSyncService } from './services/cloud/CloudConfigSyncService';
import { RuntimeStatsService } from './services/runtime/RuntimeStatsService';
import { common } from '@kit.AbilityKit';

@LogLocate("AppManager")
export class AppManager {
  private static initialized: boolean = false
  private static initPromise: Promise<void> | undefined = undefined

  public static data: DataUtil = new DataUtil()
  public static content: ContextUtil = new ContextUtil()
  public static easytier: EasyTierUtil = new EasyTierUtil()
  public static permission: PermissionUtil = new PermissionUtil()
  public static preference: PreferenceUtil = new PreferenceUtil()
  public static web: WebUtil = new WebUtil()
  public static uiState: UIState = new UIState()
  public static cloudSync: CloudConfigSyncService = new CloudConfigSyncService()
  public static runtimeStats: RuntimeStatsService = new RuntimeStatsService()

  static async init(uiContext: UIContext) {
    AppManager.content.init(uiContext)
    AppManager.permission.updatePermStatus()
    if (AppManager.initialized) {
      return
    }
    if (AppManager.initPromise) {
      await AppManager.initPromise
      return
    }
    AppManager.initPromise = (async () => {
      await AppManager.preference.init(AppManager.content.context!)
      await AppManager.cloudSync.init(AppManager.content.context! as common.UIAbilityContext)
      await AppManager.runtimeStats.init(AppManager.content.context! as common.UIAbilityContext)
      AppManager.initialized = true
    })()
    try {
      await AppManager.initPromise
    } catch (error) {
      AppManager.initPromise = undefined
      if (error instanceof Error) {
        throw error
      }
      throw new Error(`AppManager init failed: ${JSON.stringify(error)}`)
    }
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
