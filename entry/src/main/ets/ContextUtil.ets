import { Context } from "@kit.AbilityKit"
import { PreferenceUtil } from "./PreferencesUtil"
import { preferences } from "@kit.ArkData"
import { Logger, LogLocate } from "./util/Logger"
import { ContentUtil } from "./ContentUtil"
import { MeasureUtils } from "@kit.ArkUI"
import { updateSharedPeers } from "./WebUtil"
import { DataUtil } from "./DataUtil"

@LogLocate("ContextUtil")
@ObservedV2
export class ContextUtil {
  @Trace public static uiContext: UIContext | undefined
  @Trace public static context: Context | undefined
  @Trace public static measure: MeasureUtils | undefined

  public static init(uiContext: UIContext) {
    ContextUtil.uiContext = uiContext
    Logger.info("init uiContext and context", ContextUtil)
    ContextUtil.context = uiContext.getHostContext()
    ContextUtil.measure = uiContext.getMeasureUtils()
    ContentUtil.initConfigFields()
    DataUtil.init()
    updateSharedPeers()
    try {
      PreferenceUtil.preferences =
        preferences.getPreferencesSync(ContextUtil.context, { name: 'EasyTierPreferences' });
    } catch (error) {
      Logger.error(`PreferenceUtil failed to init.\n${error}`, ContextUtil)
    }
  }
}

export function Spx2vp(px: number): number {
  if (ContextUtil.uiContext) {
    return ContextUtil.uiContext.px2vp(px)
  }else {
    return px2vp(px)
  }
}

export function Spx2fp(px: number): number {
  if (ContextUtil.uiContext) {
    return ContextUtil.uiContext.px2fp(px)
  }else {
    return px2fp(px)
  }
}

export function Svp2px(px: number): number {
  if (ContextUtil.uiContext) {
    return ContextUtil.uiContext.vp2px(px)
  }else {
    return vp2px(px)
  }
}

export function Sfp2px(px: number): number {
  if (ContextUtil.uiContext) {
    return ContextUtil.uiContext.fp2px(px)
  }else {
    return fp2px(px)
  }
}

export function Sfp2vp(fp: number): number {
  return Spx2vp(Sfp2px(fp))
}

export function Svp2fp(vp: number): number {
  return Spx2fp(Svp2px(vp))
}