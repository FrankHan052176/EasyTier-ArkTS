import { buffer, util } from '@kit.ArkTS'
import { socket } from '@kit.NetworkKit'
import { RuntimeAggregateState } from '../../types/runtime/RuntimeTypes'
import {
  RuntimePeerEventPayload,
  TrafficStatsPayload,
  VpnLogData,
  VpnMessage,
  VpnRuntimeCommandData,
  VpnRuntimeCommandName,
  VpnRuntimeCommandResultData,
  VpnRuntimeStatusData,
  VPN_MESSAGE_RUNTIME_COMMAND
} from '../../infrastructure/bridge/kernel/KernelBridgeTypes'
import {
  connectVpnExtensionSocket,
  VpnExtensionSocketBridgeCallbacks
} from '../../infrastructure/bridge/kernel/VpnExtensionSocketBridge'
import { Logger } from '../../shared/logging/Logger'

export interface VpnExtensionRuntimeClientOptions {
  shouldConnect: () => boolean
  getSocketPath: (socketName: string) => string
  onTopology: (snapshot: RuntimeAggregateState) => void
  onTrafficStats: (stats: TrafficStatsPayload) => void
  onPeerEvent: (event: RuntimePeerEventPayload) => void
  onLogs: (logs: VpnLogData) => void
  onRuntimeCommandResult: (result: VpnRuntimeCommandResultData) => void
  onRuntimeStatus: (status: VpnRuntimeStatusData) => void
}

export class VpnExtensionRuntimeClient {
  private readonly options: VpnExtensionRuntimeClientOptions
  private client: socket.LocalSocket | undefined = undefined
  private connected: boolean = false
  private socketName: string = ''
  private generation: number = 0
  private connectionAttempt: number = 0
  private reconnectTimer: number = -1
  private commandGeneration: number = 0
  private inFlightRequestId: string = ''
  private pendingCommands: VpnRuntimeCommandData[] = []

  constructor(options: VpnExtensionRuntimeClientOptions) {
    this.options = options
  }

  isConnected(): boolean {
    return this.connected
  }

  connect(socketName: string): void {
    if (this.socketName === socketName && this.client !== undefined) {
      return
    }
    this.generation++
    this.socketName = socketName
    if (this.reconnectTimer >= 0) {
      clearTimeout(this.reconnectTimer)
      this.reconnectTimer = -1
    }
    this.connectGeneration(this.generation)
  }

  enqueueCommand(command: VpnRuntimeCommandName, instanceId: string): VpnRuntimeCommandData {
    const request: VpnRuntimeCommandData = {
      requestId: util.generateRandomUUID().toLowerCase(),
      generation: ++this.commandGeneration,
      command,
      instanceId
    }
    this.pendingCommands.push(request)
    this.sendNextCommand(this.generation, this.connectionAttempt)
    return request
  }

  cancelCommand(requestId: string): void {
    const index = this.pendingCommands.findIndex((request: VpnRuntimeCommandData) => {
      return request.requestId === requestId
    })
    if (index < 0) {
      return
    }
    this.pendingCommands.splice(index, 1)
    if (this.inFlightRequestId === requestId) {
      this.inFlightRequestId = ''
    }
    this.sendNextCommand(this.generation, this.connectionAttempt)
  }

  private connectGeneration(generation: number): void {
    if (generation !== this.generation || this.socketName.length === 0 || !this.options.shouldConnect()) {
      return
    }
    const attempt = ++this.connectionAttempt
    const callbacks: VpnExtensionSocketBridgeCallbacks = {
      shouldConnect: () => {
        return generation === this.generation && attempt === this.connectionAttempt && this.options.shouldConnect()
      },
      getSocketPath: this.options.getSocketPath,
      onConnected: () => {
        if (generation !== this.generation || attempt !== this.connectionAttempt) {
          return
        }
        this.connected = true
        this.inFlightRequestId = ''
        this.sendNextCommand(generation, attempt)
      },
      onDisconnected: () => {
        if (generation !== this.generation || attempt !== this.connectionAttempt) {
          return
        }
        this.connected = false
        this.inFlightRequestId = ''
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
      onRuntimeCommandResult: (result: VpnRuntimeCommandResultData) => {
        if (generation === this.generation && attempt === this.connectionAttempt) {
          this.options.onRuntimeCommandResult(result)
          this.acknowledgeCommand(result.requestId)
        }
      },
      onRuntimeStatus: (status: VpnRuntimeStatusData) => {
        if (generation === this.generation && attempt === this.connectionAttempt) {
          this.options.onRuntimeStatus(status)
        }
      }
    }
    this.client = connectVpnExtensionSocket(this.socketName, this.client, callbacks)
  }

  private acknowledgeCommand(requestId: string): void {
    const index = this.pendingCommands.findIndex((request: VpnRuntimeCommandData) => {
      return request.requestId === requestId
    })
    if (index >= 0) {
      this.pendingCommands.splice(index, 1)
    }
    if (this.inFlightRequestId === requestId) {
      this.inFlightRequestId = ''
    }
    this.sendNextCommand(this.generation, this.connectionAttempt)
  }

  private sendNextCommand(generation: number, attempt: number): void {
    const client = this.client
    if (!this.connected || !client || this.inFlightRequestId.length > 0 || this.pendingCommands.length === 0 ||
      generation !== this.generation || attempt !== this.connectionAttempt) {
      return
    }
    const request = this.pendingCommands[0]
    const rawMessage = JSON.stringify({
      type: VPN_MESSAGE_RUNTIME_COMMAND,
      data: request
    } as VpnMessage) + '\n'
    this.inFlightRequestId = request.requestId
    client.send({ data: buffer.from(rawMessage).buffer }).then(() => {
      Logger.info(`sent VPN runtime command=${request.command} instance=${request.instanceId} request=${request.requestId}`,
        'VpnExtensionRuntimeClient')
    }).catch((error: object) => {
      Logger.error(`sending VPN runtime command failed: ${JSON.stringify(error)}`, 'VpnExtensionRuntimeClient')
      if (generation === this.generation && attempt === this.connectionAttempt) {
        this.inFlightRequestId = ''
        void client.close()
      }
    })
  }

  private scheduleReconnect(generation: number, attempt: number): void {
    if (generation !== this.generation || attempt !== this.connectionAttempt || !this.options.shouldConnect() ||
      this.reconnectTimer >= 0) {
      return
    }
    this.reconnectTimer = setTimeout(() => {
      this.reconnectTimer = -1
      this.client = undefined
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
    this.connected = false
    this.inFlightRequestId = ''
    this.pendingCommands = []
  }
}
