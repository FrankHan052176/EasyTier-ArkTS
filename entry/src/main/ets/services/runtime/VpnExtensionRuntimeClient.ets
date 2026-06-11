import { socket } from '@kit.NetworkKit'
import { RuntimeAggregateState } from '../../types/runtime/RuntimeTypes'
import {
  RuntimePeerEventPayload,
  TrafficStatsPayload,
  VpnLogData
} from '../../infrastructure/bridge/kernel/KernelBridgeTypes'
import {
  connectVpnExtensionSocket,
  VpnExtensionSocketBridgeCallbacks
} from '../../infrastructure/bridge/kernel/VpnExtensionSocketBridge'

export interface VpnExtensionRuntimeClientOptions {
  isExtMode: () => boolean
  getSocketPath: (socketName: string) => string
  onTopology: (snapshot: RuntimeAggregateState) => void
  onTrafficStats: (stats: TrafficStatsPayload) => void
  onPeerEvent: (event: RuntimePeerEventPayload) => void
  onLogs: (logs: VpnLogData) => void
}

export class VpnExtensionRuntimeClient {
  private readonly options: VpnExtensionRuntimeClientOptions
  private client: socket.LocalSocket | undefined = undefined
  private connected: boolean = false

  constructor(options: VpnExtensionRuntimeClientOptions) {
    this.options = options
  }

  isConnected(): boolean {
    return this.connected
  }

  connect(socketName: string): void {
    const callbacks: VpnExtensionSocketBridgeCallbacks = {
      isExtMode: this.options.isExtMode,
      getSocketPath: this.options.getSocketPath,
      onConnected: () => {
        this.connected = true
      },
      onDisconnected: () => {
        this.connected = false
      },
      onTopology: this.options.onTopology,
      onTrafficStats: this.options.onTrafficStats,
      onPeerEvent: this.options.onPeerEvent,
      onLogs: this.options.onLogs
    }
    this.client = connectVpnExtensionSocket(socketName, this.client, callbacks)
  }

  close(): void {
    this.client?.close()
    this.client = undefined
    this.connected = false
  }
}
