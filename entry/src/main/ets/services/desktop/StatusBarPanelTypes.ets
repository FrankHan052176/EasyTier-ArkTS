export const STATUS_BAR_PANEL_SOCKET_NAME = 'easytier-statusbar.sock'
export const STATUS_BAR_PANEL_MESSAGE_STATE = 'state'
export const STATUS_BAR_PANEL_MESSAGE_ACTION = 'action'
export const STATUS_BAR_PANEL_ACTION_REQUEST_STATE = 'request_state'
export const STATUS_BAR_PANEL_ACTION_OPEN_APP = 'open_app'
export const STATUS_BAR_PANEL_ACTION_TOGGLE_FAVORITE = 'toggle_favorite'
export const STATUS_BAR_PANEL_ACTION_STOP_ALL = 'stop_all'

export interface StatusBarPanelState {
  selectedName: string
  favoriteName: string
  favoriteUuid: string
  favoriteRunning: boolean
  runningCount: number
  configCount: number
  keepAliveMode: string
}

export interface StatusBarPanelMessage {
  type: string
  action?: string
  state?: StatusBarPanelState
}

export function emptyStatusBarPanelState(): StatusBarPanelState {
  return {
    selectedName: '未选择实例',
    favoriteName: '未收藏实例',
    favoriteUuid: '',
    favoriteRunning: false,
    runningCount: 0,
    configCount: 0,
    keepAliveMode: 'dataTransfer'
  }
}
