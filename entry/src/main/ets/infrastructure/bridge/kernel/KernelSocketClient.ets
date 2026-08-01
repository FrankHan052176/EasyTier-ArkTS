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
  onRetry?: (retryCount: number, error: BusinessError) => void
  onClosed?: () => void
  onMessage: (message: KernelSocketMessage) => void
}

export class KernelSocketClient {
  private client: socket.LocalSocket | undefined = undefined
  private messageBuffer: string = ''
  private connected: boolean = false
  private active: boolean = false
  private generation: number = 0
  private reconnectTimer: number = -1
  private options: KernelSocketClientOptions | undefined = undefined

  isConnected(): boolean {
    return this.connected
  }

  close(): void {
    this.active = false
    this.generation++
    if (this.reconnectTimer >= 0) {
      clearTimeout(this.reconnectTimer)
      this.reconnectTimer = -1
    }
    const client = this.client
    this.client = undefined
    client?.close()
    this.messageBuffer = ''
    this.connected = false
    this.options = undefined
  }

  start(options: KernelSocketClientOptions): void {
    this.close()
    this.active = true
    this.options = options
    this.generation++
    this.scheduleReconnect(this.generation, 0, options.initialDelayMs ?? 200)
  }

  private scheduleReconnect(generation: number, retryCount: number, delayMs?: number): void {
    if (!this.canConnect(generation)) {
      return
    }
    if (this.reconnectTimer >= 0) {
      clearTimeout(this.reconnectTimer)
    }
    const options = this.options!
    const baseDelay = options.retryDelayMs ?? 500
    const computedDelay = Math.min(baseDelay * Math.max(1, retryCount), 5000)
    this.reconnectTimer = setTimeout(() => {
      this.reconnectTimer = -1
      this.createAndConnect(generation, retryCount)
    }, delayMs ?? computedDelay)
  }

  private canConnect(generation: number): boolean {
    if (!this.active || this.generation !== generation || !this.options) {
      return false
    }
    return this.options.shouldConnect ? this.options.shouldConnect() : true
  }

  private createAndConnect(generation: number, retryCount: number): void {
    if (!this.canConnect(generation)) {
      return
    }
    const options = this.options!
    const oldClient = this.client
    this.client = undefined
    oldClient?.close()
    const client = socket.constructLocalSocketInstance()
    this.client = client
    this.messageBuffer = ''
    this.connected = false

    const address: socket.LocalConnectOptions = {
      address: {
        address: options.socketPath
      }
    }
    client.connect(address).then(() => {
      if (this.client !== client || !this.canConnect(generation)) {
        return
      }
      this.connected = true
      options.onConnected?.()
    }).catch((error: BusinessError) => {
      if (this.client !== client || !this.canConnect(generation)) {
        return
      }
      this.connected = false
      options.onRetry?.(retryCount, error)
      const retryLimit = options.retryLimit ?? 20
      const nextRetry = Math.min(retryCount + 1, retryLimit)
      this.scheduleReconnect(generation, nextRetry)
    })

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
      this.scheduleReconnect(generation, 1)
    })
  }
}
