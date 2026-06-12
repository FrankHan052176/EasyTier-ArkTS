import { common } from '@kit.AbilityKit'
import { JSON, buffer } from '@kit.ArkTS'
import { BusinessError } from '@kit.BasicServicesKit'
import { fileIo } from '@kit.CoreFileKit'
import { socket } from '@kit.NetworkKit'
import { AppManager } from '../../AppManager'
import { decodeSocketChunk } from '../../infrastructure/bridge/kernel/SocketCodec'
import { Logger } from '../../shared/logging/Logger'
import { EventHelper } from '../../util/EventHelper'
import { backgroundKeepAliveModeText } from '../../types/runtime/BackgroundKeepAliveTypes'
import {
  STATUS_BAR_PANEL_ACTION_OPEN_APP,
  STATUS_BAR_PANEL_ACTION_REQUEST_STATE,
  STATUS_BAR_PANEL_ACTION_STOP_ALL,
  STATUS_BAR_PANEL_ACTION_TOGGLE_FAVORITE,
  STATUS_BAR_PANEL_MESSAGE_ACTION,
  STATUS_BAR_PANEL_MESSAGE_STATE,
  StatusBarPanelMessage,
  StatusBarPanelState
} from './StatusBarPanelTypes'

export class StatusBarPanelServer {
  private readonly context: common.UIAbilityContext
  private readonly logTarget: Object | string
  private readonly openMainWindow: (() => void) | undefined
  private server: socket.LocalSocketServer | undefined
  private readonly connections: Map<number, socket.LocalSocketConnection> = new Map()
  private readonly buffers: Map<number, string> = new Map()
  private refreshTimer: number | undefined

  constructor(context: common.UIAbilityContext, logTarget: Object | string, openMainWindow?: () => void) {
    this.context = context
    this.logTarget = logTarget
    this.openMainWindow = openMainWindow
  }

  start(socketPath: string): void {
    if (this.server) {
      return
    }
    this.server = socket.constructLocalSocketServerInstance()
    try {
      fileIo.unlinkSync(socketPath)
    } catch (_) {
    }
    this.server.listen({ address: socketPath }).then(() => {
      Logger.info(`status bar panel socket listening: ${socketPath}`, this.logTarget)
    }).catch((err: object) => {
      Logger.error(`status bar panel listen failed: ${JSON.stringify(err)}`, this.logTarget)
    })
    this.server.on('connect', (connection: socket.LocalSocketConnection) => {
      this.connections.set(connection.clientId, connection)
      this.buffers.set(connection.clientId, '')
      this.sendState(connection)
      connection.on('message', (value: socket.LocalSocketMessageInfo) => {
        this.handleMessage(connection, value.message)
      })
      connection.on('close', () => {
        this.drop(connection)
      })
      connection.on('error', (err: object) => {
        Logger.debug(`status bar panel connection error: ${JSON.stringify(err)}`, this.logTarget)
        this.drop(connection)
      })
    })
    this.refreshTimer = setInterval(() => {
      if (this.connections.size > 0) {
        this.broadcastState()
      }
    }, 1000)
  }

  close(): void {
    if (this.refreshTimer !== undefined) {
      clearInterval(this.refreshTimer)
      this.refreshTimer = undefined
    }
    this.connections.forEach((connection) => {
      try {
        connection.close()
      } catch (_) {
      }
    })
    this.connections.clear()
    this.buffers.clear()
    try {
      this.server?.close()
    } catch (error) {
      Logger.debug(`status bar panel server close ignored: ${JSON.stringify(error)}`, this.logTarget)
    }
    this.server = undefined
  }

  broadcastState(): void {
    this.connections.forEach((connection) => {
      this.sendState(connection)
    })
  }

  private buildState(): StatusBarPanelState {
    const selected = AppManager.uiState.selected ?? ''
    const favorite = AppManager.uiState.favorite ?? ''
    return {
      selectedName: selected ? AppManager.easytier.getConfigName(selected) ?? selected : '未选择实例',
      favoriteName: favorite ? AppManager.easytier.getConfigName(favorite) ?? favorite : '未收藏实例',
      favoriteUuid: favorite,
      favoriteRunning: AppManager.easytier.isFavoritesRunning(),
      runningCount: AppManager.easytier.runningNetworks.size,
      configCount: AppManager.data.configIds.length,
      keepAliveMode: backgroundKeepAliveModeText(AppManager.uiState.background_keep_alive_mode)
    }
  }

  private handleMessage(connection: socket.LocalSocketConnection, raw: ArrayBuffer | Uint8Array | string): void {
    try {
      const decoded = decodeSocketChunk(this.buffers.get(connection.clientId) ?? '', raw)
      this.buffers.set(connection.clientId, decoded.rest)
      decoded.messages.forEach((messageText) => {
        const message = JSON.parse(messageText) as StatusBarPanelMessage
        if (message.type === STATUS_BAR_PANEL_MESSAGE_ACTION) {
          this.handleAction(connection, message.action ?? '')
        }
      })
    } catch (error) {
      Logger.error(`status bar panel message parse failed: ${JSON.stringify(error)}`, this.logTarget)
    }
  }

  private handleAction(connection: socket.LocalSocketConnection, action: string): void {
    switch (action) {
      case STATUS_BAR_PANEL_ACTION_REQUEST_STATE:
        this.sendState(connection)
        break
      case STATUS_BAR_PANEL_ACTION_OPEN_APP:
        this.openApp()
        break
      case STATUS_BAR_PANEL_ACTION_TOGGLE_FAVORITE:
        this.toggleFavorite()
        break
      case STATUS_BAR_PANEL_ACTION_STOP_ALL:
        AppManager.easytier.stop()
        break
    }
    setTimeout(() => {
      this.broadcastState()
    }, 120)
  }

  private openApp(): void {
    this.openMainWindow?.()
    this.context.startAbility({
      bundleName: EventHelper.bundleName,
      abilityName: 'EntryAbility'
    }).catch((err: BusinessError) => {
      Logger.error(`status bar open app failed: ${err.code}, ${err.message}`, this.logTarget)
    })
  }

  private toggleFavorite(): void {
    const favorite = AppManager.uiState.favorite
    if (!favorite) {
      return
    }
    if (AppManager.easytier.isFavoritesRunning()) {
      AppManager.easytier.stopConfig(favorite)
      return
    }
    if (AppManager.easytier.runningNetworks.size > 0) {
      AppManager.easytier.stop()
    }
    AppManager.easytier.start(favorite, true)
  }

  private sendState(connection: socket.LocalSocketConnection): void {
    this.send(connection, {
      type: STATUS_BAR_PANEL_MESSAGE_STATE,
      state: this.buildState()
    })
  }

  private send(connection: socket.LocalSocketConnection, message: StatusBarPanelMessage): void {
    connection.send({ data: buffer.from(JSON.stringify(message) + '\n').buffer }).catch((err: BusinessError) => {
      this.drop(connection)
      Logger.debug(`status bar panel send failed: ${err.code}, ${err.message}`, this.logTarget)
    })
  }

  private drop(connection: socket.LocalSocketConnection): void {
    this.connections.delete(connection.clientId)
    this.buffers.delete(connection.clientId)
  }
}
