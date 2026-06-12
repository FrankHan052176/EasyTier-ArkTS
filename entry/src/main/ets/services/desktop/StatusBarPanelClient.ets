import { JSON, buffer } from '@kit.ArkTS'
import { BusinessError } from '@kit.BasicServicesKit'
import { socket } from '@kit.NetworkKit'
import { decodeSocketChunk } from '../../infrastructure/bridge/kernel/SocketCodec'
import { Logger } from '../../shared/logging/Logger'
import {
  STATUS_BAR_PANEL_ACTION_REQUEST_STATE,
  STATUS_BAR_PANEL_MESSAGE_ACTION,
  STATUS_BAR_PANEL_MESSAGE_STATE,
  StatusBarPanelMessage,
  StatusBarPanelState
} from './StatusBarPanelTypes'

export interface StatusBarPanelClientOptions {
  socketPath: string
  logTarget: Object | string
  onState: (state: StatusBarPanelState) => void
  onConnectionChanged?: (connected: boolean) => void
}

export class StatusBarPanelClient {
  private client: socket.LocalSocket | undefined
  private messageBuffer: string = ''
  private connected: boolean = false

  connect(options: StatusBarPanelClientOptions): void {
    this.close()
    const client = socket.constructLocalSocketInstance()
    this.client = client
    this.messageBuffer = ''
    this.connected = false
    client.connect({ address: { address: options.socketPath } }).then(() => {
      if (this.client !== client) {
        return
      }
      this.connected = true
      options.onConnectionChanged?.(true)
      this.sendAction(STATUS_BAR_PANEL_ACTION_REQUEST_STATE)
    }).catch((err: BusinessError) => {
      if (this.client !== client) {
        return
      }
      Logger.debug(`status bar panel connect failed: ${err.code}, ${err.message}`, options.logTarget)
      options.onConnectionChanged?.(false)
    })

    client.on('message', (value: socket.LocalSocketMessageInfo) => {
      if (this.client !== client) {
        return
      }
      try {
        const decoded = decodeSocketChunk(this.messageBuffer, value.message)
        this.messageBuffer = decoded.rest
        decoded.messages.forEach((messageText) => {
          const message = JSON.parse(messageText) as StatusBarPanelMessage
          if (message.type === STATUS_BAR_PANEL_MESSAGE_STATE && message.state) {
            options.onState(message.state)
          }
        })
      } catch (error) {
        Logger.error(`status bar panel client message failed: ${JSON.stringify(error)}`, options.logTarget)
      }
    })

    client.on('close', () => {
      if (this.client !== client) {
        return
      }
      this.connected = false
      options.onConnectionChanged?.(false)
    })
  }

  close(): void {
    this.client?.close()
    this.client = undefined
    this.messageBuffer = ''
    this.connected = false
  }

  sendAction(action: string): void {
    if (!this.client || !this.connected) {
      return
    }
    const message: StatusBarPanelMessage = {
      type: STATUS_BAR_PANEL_MESSAGE_ACTION,
      action
    }
    this.client.send({ data: buffer.from(JSON.stringify(message) + '\n').buffer }).catch((err: BusinessError) => {
      Logger.debug(`status bar panel action failed: ${err.code}, ${err.message}`, 'StatusBarPanelClient')
    })
  }
}
