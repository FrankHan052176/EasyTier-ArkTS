import { JSON } from '@kit.ArkTS'
import { BusinessError } from '@kit.BasicServicesKit'
import {
  KernelSocketMessage,
  KERNEL_MESSAGE_RUNTIME_PEER_EVENT,
  KERNEL_MESSAGE_RUNTIME_TOPOLOGY,
  KERNEL_MESSAGE_TRAFFIC_STATS,
  KERNEL_MESSAGE_TUN_REQUEST,
  RuntimePeerEventPayload,
  TrafficStatsPayload,
  TunRequestPayload
} from '../../infrastructure/bridge/kernel/KernelBridgeTypes'
import { KernelSocketClient } from '../../infrastructure/bridge/kernel/KernelSocketClient'
import { Logger } from '../../shared/logging/Logger'
import {
  KERNEL_RUNTIME_PEER_EVENT,
  KERNEL_RUNTIME_TOPOLOGY_EVENT,
  KERNEL_TRAFFIC_STATS_EVENT
} from '../../types/events/RuntimeEventTypes'
import { RuntimeAggregateState } from '../../types/runtime/RuntimeTypes'
import { EventHelper } from '../../util/EventHelper'
import { EntryVpnSetupRequest } from '../tun/EntryVpnConnectionService'

export interface EntryKernelSocketServiceOptions {
  logTarget: Object | string
  shouldConnect: () => boolean
  buildTunSetupRequest: (payload: TunRequestPayload) => EntryVpnSetupRequest
  setupTun: (request: EntryVpnSetupRequest) => void
}

export class EntryKernelSocketService {
  private readonly logTarget: Object | string
  private readonly shouldConnect: () => boolean
  private readonly buildTunSetupRequest: (payload: TunRequestPayload) => EntryVpnSetupRequest
  private readonly setupTun: (request: EntryVpnSetupRequest) => void
  private kernelSocketClient: KernelSocketClient | undefined = undefined

  constructor(options: EntryKernelSocketServiceOptions) {
    this.logTarget = options.logTarget
    this.shouldConnect = options.shouldConnect
    this.buildTunSetupRequest = options.buildTunSetupRequest
    this.setupTun = options.setupTun
  }

  connect(socketPath: string): void {
    if (this.kernelSocketClient?.isConnected()) {
      return
    }
    this.kernelSocketClient?.close()
    this.kernelSocketClient = new KernelSocketClient()
    this.kernelSocketClient.start({
      socketPath,
      logTarget: this.logTarget,
      shouldConnect: this.shouldConnect,
      onConnected: () => {
        Logger.info('Connected to kernel socket', this.logTarget)
      },
      onRetry: (retryCount: number, error: BusinessError) => {
        Logger.info(`kernel socket connect retry=${retryCount} code=${error.code} message=${error.message}`, this.logTarget)
      },
      onMessage: (msg: KernelSocketMessage) => {
        this.handleMessage(msg)
      }
    })
  }

  close(): void {
    this.kernelSocketClient?.close()
    this.kernelSocketClient = undefined
  }

  reconnect(socketPath: string): void {
    this.close()
    this.connect(socketPath)
  }

  isConnected(): boolean {
    return this.kernelSocketClient?.isConnected() ?? false
  }

  private handleMessage(msg: KernelSocketMessage): void {
    if (msg.messageType === KERNEL_MESSAGE_RUNTIME_TOPOLOGY) {
      const snapshot = typeof msg.payloadJson === 'string' ? JSON.parse(msg.payloadJson) as RuntimeAggregateState : msg.payloadJson as RuntimeAggregateState
      EventHelper.emitterPublish(KERNEL_RUNTIME_TOPOLOGY_EVENT, {
        data: {
          snapshot
        }
      })
    } else if (msg.messageType === KERNEL_MESSAGE_RUNTIME_PEER_EVENT) {
      const peerEvent = typeof msg.payloadJson === 'string' ? JSON.parse(msg.payloadJson) as RuntimePeerEventPayload : msg.payloadJson as RuntimePeerEventPayload
      EventHelper.emitterPublish(KERNEL_RUNTIME_PEER_EVENT, {
        data: {
          peerEvent
        }
      })
    } else if (msg.messageType === KERNEL_MESSAGE_TRAFFIC_STATS) {
      const stats = typeof msg.payloadJson === 'string' ? JSON.parse(msg.payloadJson) as TrafficStatsPayload : msg.payloadJson as TrafficStatsPayload
      EventHelper.emitterPublish(KERNEL_TRAFFIC_STATS_EVENT, {
        data: {
          stats
        }
      })
    } else if (msg.messageType === KERNEL_MESSAGE_TUN_REQUEST) {
      const payload = typeof msg.payloadJson === 'string' ? JSON.parse(msg.payloadJson) as TunRequestPayload : msg.payloadJson as TunRequestPayload
      this.setupTun(this.buildTunSetupRequest(payload))
    }
  }
}
