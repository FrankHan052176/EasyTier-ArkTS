import { BusinessError } from '@kit.BasicServicesKit'
import { socket } from '@kit.NetworkKit'
import { Logger } from '../../../shared/logging/Logger'
import { KernelSocketMessage } from './KernelBridgeTypes'
import { decodeSocketChunk, parseKernelSocketMessage } from './SocketCodec'

export interface KernelSocketClientOptions {
  socketPath: string
  logTarget: Object | string
  retryLimit?: number
  retryDelayMs?: number
  initialDelayMs?: number
  shouldConnect?: () => boolean
  onConnected?: () => void
  onConnectError?: (error: BusinessError) => boolean
  onRetry?: (retryCount: number, error: BusinessError) => void
  onClosed?: () => void
  onMessage: (message: KernelSocketMessage) => void
}

export class KernelSocketClient {
  private client: socket.LocalSocket | undefined = undefined
  private messageBuffer: string = ''
  private connected: boolean = false

  isConnected(): boolean {
    return this.connected
  }

  close(): void {
    this.client?.close()
    this.client = undefined
    this.messageBuffer = ''
    this.connected = false
  }

  start(options: KernelSocketClientOptions): void {
    this.close()
    const client = socket.constructLocalSocketInstance()
    this.client = client
    this.messageBuffer = ''
    this.connected = false

    const address: socket.LocalConnectOptions = {
      address: {
        address: options.socketPath
      }
    }
    const retryLimit = options.retryLimit ?? 20
    const retryDelayMs = options.retryDelayMs ?? 500
    const initialDelayMs = options.initialDelayMs ?? 200
    let retryCount = 0

    const canConnect = (): boolean => {
      return this.client === client && (options.shouldConnect ? options.shouldConnect() : true)
    }
    const connect = () => {
      if (!canConnect()) {
        return
      }
      client.connect(address).then(() => {
        if (this.client !== client) {
          return
        }
        this.connected = true
        options.onConnected?.()
      }).catch((error: BusinessError) => {
        if (this.client !== client) {
          return
        }
        if (options.onConnectError?.(error)) {
          this.connected = true
          return
        }
        options.onRetry?.(retryCount, error)
        if (retryCount < retryLimit && canConnect()) {
          retryCount++
          setTimeout(connect, retryDelayMs)
        }
      })
    }
    setTimeout(connect, initialDelayMs)

    client.on('message', (value: socket.LocalSocketMessageInfo) => {
      if (this.client !== client) {
        return
      }
      try {
        const decoded = decodeSocketChunk(this.messageBuffer, value.message)
        this.messageBuffer = decoded.rest
        for (const rawMessage of decoded.messages) {
          options.onMessage(parseKernelSocketMessage(rawMessage))
        }
      } catch (error) {
        Logger.error(`kernel socket message error: ${JSON.stringify(error)}`, options.logTarget)
      }
    })

    client.on('close', () => {
      if (this.client !== client) {
        return
      }
      this.connected = false
      options.onClosed?.()
    })
  }
}
