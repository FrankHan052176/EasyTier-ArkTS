export const APP_BUNDLE_NAME = 'top.frankhan.easytier'
export const ENTRY_MODULE_NAME = 'entry'
export const ENTRY_ABILITY_NAME = 'EntryAbility'
export const ENTRY_FORM_ABILITY_NAME = 'EntryFormAbility'
export const VPN_EXTENSION_ABILITY_NAME = 'EasyTierAbility'
export const STATUS_BAR_VIEW_ABILITY_NAME = 'StatusBarViewAbility'
export const STATUS_BAR_BACKGROUND_ABILITY_NAME = 'StatusBarBackgroundAbility'
export const VPN_EXTENSION_SOCKET_NAME = 'easytier_vpn_socket'

export const STATUS_BAR_BACKGROUND_TERMINATE_EVENT = `${APP_BUNDLE_NAME}.statusBarBackgroundTerminate`

export const STATUS_BAR_MANAGER_SYSCAP = 'SystemCapability.PCService.StatusBarManager'
export const CONTINUOUS_BACKGROUND_TASK_SYSCAP = 'SystemCapability.ResourceSchedule.BackgroundTaskManager.ContinuousTask'

export function supportsStatusBarTray(): boolean {
  return canIUse(STATUS_BAR_MANAGER_SYSCAP)
}

export function shouldUseEntryBackgroundKeepAlive(): boolean {
  return !supportsStatusBarTray()
}

export function shouldUseSubprocessRuntimeMode(): boolean {
  return !supportsStatusBarTray()
}
