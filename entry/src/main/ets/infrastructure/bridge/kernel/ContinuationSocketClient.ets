import { socket } from '@kit.NetworkKit'
import { Logger } from '../../../shared/logging/Logger'
import { VpnContinueStateData } from './KernelBridgeTypes'
import { decodeSocketChunk, parseVpnBridgeMessage } from './SocketCodec'

export interface ContinuationSocketClientOptions {
  socketName: string
  logTarget: Object | string
  isExtMode: () => boolean
  getSocketPath: (socketName: string) => string
  onContinueState: (active: boolean) => void
  initialDelayMs?: number
  retryDelayMs?: number
}

export class ContinuationSocketClient {
  private client: socket.LocalSocket | undefined = undefined
  private messageBuffer: string = ''
  private connected: boolean = false
  private readonly options: ContinuationSocketClientOptions

  constructor(options: ContinuationSocketClientOptions) {
    this.options = options
  }

  isConnected(): boolean {
    return this.connected
  }

  sync(): void {
    if (!this.options.isExtMode()) {
      this.close()
      return
    }
    if (this.connected) {
      return
    }
    this.discardClient()

    const client = socket.constructLocalSocketInstance()
    this.client = client
    this.messageBuffer = ''
    const address: socket.LocalConnectOptions = {
      address: {
        address: this.options.getSocketPath(this.options.socketName)
      }
    }
    const initialDelayMs = this.options.initialDelayMs ?? 200
    const retryDelayMs = this.options.retryDelayMs ?? 500

    const reconnect = (): void => {
      if (!this.options.isExtMode() || this.connected) {
        return
      }
      setTimeout(() => {
        this.sync()
      }, retryDelayMs)
    }

    setTimeout(() => {
      if (this.client !== client || !this.options.isExtMode()) {
        return
      }
      client.connect(address).then(() => {
        if (this.client !== client) {
          return
        }
        this.connected = true
        Logger.info('Connected to continuation socket', this.options.logTarget)
      }).catch((error: object) => {
        if (this.client !== client) {
          return
        }
        Logger.debug(`continuation socket retry error=${JSON.stringify(error)}`, this.options.logTarget)
        reconnect()
      })
    }, initialDelayMs)

    client.on('message', (value: socket.LocalSocketMessageInfo) => {
      if (this.client !== client) {
        return
      }
      try {
        const decoded = decodeSocketChunk(this.messageBuffer, value.message)
        this.messageBuffer = decoded.rest
        for (const rawMessage of decoded.messages) {
          const msg = parseVpnBridgeMessage(rawMessage)
          if (msg.type === 'continue_state') {
            const state = msg.data as VpnContinueStateData
            this.options.onContinueState(state.active)
          }
        }
      } catch (error) {
        Logger.error(`continuation socket message error: ${JSON.stringify(error)}`, this.options.logTarget)
      }
    })

    client.on('close', () => {
      if (this.client !== client) {
        return
      }
      this.connected = false
      this.client = undefined
      this.messageBuffer = ''
      this.options.onContinueState(false)
      reconnect()
    })
  }

  close(): void {
    this.discardClient()
    this.options.onContinueState(false)
  }

  private discardClient(): void {
    const currentClient = this.client
    this.client = undefined
    this.messageBuffer = ''
    this.connected = false
    currentClient?.close()
  }
}
