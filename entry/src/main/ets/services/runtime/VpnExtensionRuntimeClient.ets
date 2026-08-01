import { buffer } from '@kit.ArkTS'
import { socket } from '@kit.NetworkKit'
import { RuntimeAggregateState } from '../../types/runtime/RuntimeTypes'
import {
  RuntimePeerEventPayload,
  TrafficStatsPayload,
  VpnMessage,
  VpnRuntimeStartRequestData,
  VpnRuntimeStartResultData,
  VpnLogData,
  VPN_MESSAGE_RUNTIME_START_REQUEST
} from '../../infrastructure/bridge/kernel/KernelBridgeTypes'
import {
  connectVpnExtensionSocket,
  VpnExtensionSocketBridgeCallbacks
} from '../../infrastructure/bridge/kernel/VpnExtensionSocketBridge'
import { Logger } from '../../shared/logging/Logger'

export interface VpnExtensionRuntimeClientOptions {
  isExtMode: () => boolean
  getSocketPath: (socketName: string) => string
  onTopology: (snapshot: RuntimeAggregateState) => void
  onTrafficStats: (stats: TrafficStatsPayload) => void
  onPeerEvent: (event: RuntimePeerEventPayload) => void
  onLogs: (logs: VpnLogData) => void
  onRuntimeStartResult: (result: VpnRuntimeStartResultData) => void
}

export class VpnExtensionRuntimeClient {
  private readonly options: VpnExtensionRuntimeClientOptions
  private client: socket.LocalSocket | undefined = undefined
  private connected: boolean = false
  private socketName: string = ''
  private generation: number = 0
  private connectionAttempt: number = 0
  private reconnectTimer: number = -1
  private disconnectedWaiters: Array<() => void> = []
  private pendingStartRequest: VpnRuntimeStartRequestData | undefined = undefined

  constructor(options: VpnExtensionRuntimeClientOptions) {
    this.options = options
  }

  isConnected(): boolean {
    return this.connected
  }

  connect(socketName: string, startRequest?: VpnRuntimeStartRequestData): void {
    if (startRequest) {
      this.pendingStartRequest = startRequest
    }
    this.generation++
    this.socketName = socketName
    if (this.reconnectTimer >= 0) {
      clearTimeout(this.reconnectTimer)
      this.reconnectTimer = -1
    }
    this.connectGeneration(this.generation)
  }

  private connectGeneration(generation: number): void {
    if (generation !== this.generation || this.socketName.length === 0 || !this.options.isExtMode()) {
      return
    }
    const attempt = ++this.connectionAttempt
    const callbacks: VpnExtensionSocketBridgeCallbacks = {
      isExtMode: () => generation === this.generation && attempt === this.connectionAttempt && this.options.isExtMode(),
      getSocketPath: this.options.getSocketPath,
      onConnected: () => {
        if (generation !== this.generation || attempt !== this.connectionAttempt) {
          return
        }
        this.connected = true
        this.sendPendingStartRequest(generation, attempt)
      },
      onDisconnected: () => {
        if (generation !== this.generation || attempt !== this.connectionAttempt) {
          return
        }
        this.markDisconnected()
      },
      onReconnectRequested: () => {
        this.scheduleReconnect(generation, attempt)
      },
      onTopology: (snapshot: RuntimeAggregateState) => {
        if (generation === this.generation && attempt === this.connectionAttempt) {
          this.options.onTopology(snapshot)
        }
      },
      onTrafficStats: (stats: TrafficStatsPayload) => {
        if (generation === this.generation && attempt === this.connectionAttempt) {
          this.options.onTrafficStats(stats)
        }
      },
      onPeerEvent: (event: RuntimePeerEventPayload) => {
        if (generation === this.generation && attempt === this.connectionAttempt) {
          this.options.onPeerEvent(event)
        }
      },
      onLogs: (logs: VpnLogData) => {
        if (generation === this.generation && attempt === this.connectionAttempt) {
          this.options.onLogs(logs)
        }
      },
      onRuntimeStartResult: (result: VpnRuntimeStartResultData) => {
        if (generation === this.generation && attempt === this.connectionAttempt) {
          this.options.onRuntimeStartResult(result)
        }
      }
    }
    this.client = connectVpnExtensionSocket(this.socketName, this.client, callbacks)
  }

  clearRuntimeStartRequest(instanceId: string): void {
    if (this.pendingStartRequest?.instanceId === instanceId) {
      this.pendingStartRequest = undefined
    }
  }

  private sendPendingStartRequest(generation: number, attempt: number): void {
    const request = this.pendingStartRequest
    const client = this.client
    if (!request || !client || generation !== this.generation || attempt !== this.connectionAttempt) {
      return
    }
    const rawMessage = JSON.stringify({
      type: VPN_MESSAGE_RUNTIME_START_REQUEST,
      data: request
    } as VpnMessage) + '\n'
    client.send({ data: buffer.from(rawMessage).buffer }).then(() => {
      Logger.info(`sent VPN runtime request instance=${request.instanceId}`, 'VpnExtensionRuntimeClient')
    }).catch((error: object) => {
      Logger.error(`sending VPN runtime request failed: ${JSON.stringify(error)}`, 'VpnExtensionRuntimeClient')
      if (generation === this.generation && attempt === this.connectionAttempt) {
        void client.close()
      }
    })
  }

  private scheduleReconnect(generation: number, attempt: number): void {
    if (generation !== this.generation || attempt !== this.connectionAttempt || !this.options.isExtMode() ||
      this.reconnectTimer >= 0) {
      return
    }
    this.reconnectTimer = setTimeout(() => {
      this.reconnectTimer = -1
      this.connectGeneration(generation)
    }, 1000)
  }

  close(): void {
    this.generation++
    this.connectionAttempt++
    this.socketName = ''
    if (this.reconnectTimer >= 0) {
      clearTimeout(this.reconnectTimer)
      this.reconnectTimer = -1
    }
    try {
      this.client?.close()
    } catch (error) {
      Logger.debug(`closing VpnExtension runtime client failed: ${JSON.stringify(error)}`, 'VpnExtensionRuntimeClient')
    }
    this.client = undefined
    this.pendingStartRequest = undefined
    this.markDisconnected()
  }

  waitForDisconnected(timeoutMs: number = 10000): Promise<void> {
    if (!this.connected) {
      return Promise.resolve()
    }
    return new Promise<void>((resolve, reject) => {
      let completed = false
      const finish = (error: Error | undefined): void => {
        if (completed) {
          return
        }
        completed = true
        if (error) {
          reject(error)
        } else {
          resolve()
        }
      }
      const timeoutId = setTimeout(() => {
        finish(new Error('VPN extension socket did not close after stop'))
      }, timeoutMs)
      this.disconnectedWaiters.push(() => {
        clearTimeout(timeoutId)
        finish(undefined)
      })
    })
  }

  private markDisconnected(): void {
    this.connected = false
    if (this.disconnectedWaiters.length === 0) {
      return
    }
    const waiters = this.disconnectedWaiters
    this.disconnectedWaiters = []
    waiters.forEach((resolve) => {
      resolve()
    })
  }
}
