import { socket } from '@kit.NetworkKit'
import { Logger } from '../../../shared/logging/Logger'
import { RuntimeAggregateState } from '../../../types/runtime/RuntimeTypes'
import {
  KERNEL_MESSAGE_RUNTIME_PEER_EVENT,
  KERNEL_MESSAGE_RUNTIME_TOPOLOGY,
  KERNEL_MESSAGE_TRAFFIC_STATS,
  RuntimePeerEventPayload,
  TrafficStatsPayload,
  VpnLogData,
  VPN_MESSAGE_LOGS
} from './KernelBridgeTypes'
import { decodeSocketChunk, parseVpnBridgeMessage } from './SocketCodec'

export interface VpnExtensionSocketBridgeCallbacks {
  isExtMode: () => boolean
  getSocketPath: (socketName: string) => string
  onConnected: () => void
  onDisconnected: () => void
  onTopology: (snapshot: RuntimeAggregateState) => void
  onTrafficStats: (stats: TrafficStatsPayload) => void
  onPeerEvent: (event: RuntimePeerEventPayload) => void
  onLogs: (logs: VpnLogData) => void
}

export function connectVpnExtensionSocket(
  socketName: string,
  currentClient: socket.LocalSocket | undefined,
  callbacks: VpnExtensionSocketBridgeCallbacks
): socket.LocalSocket {
  currentClient?.close()
  const client = socket.constructLocalSocketInstance()
  let messageBuffer = ''
  const address: socket.LocalConnectOptions = {
    address: {
      address: callbacks.getSocketPath(socketName)
    }
  }

  let retryCount = 0
  const connect = () => {
    if (!callbacks.isExtMode()) {
      return
    }
    client.connect(address).then(() => {
      Logger.debug('Connected to VpnExtension socket', 'VpnExtensionSocketBridge')
      callbacks.onConnected()
    }).catch((_err: object) => {
      callbacks.onDisconnected()
      if (retryCount < 10 && callbacks.isExtMode()) {
        retryCount++
        setTimeout(connect, 500)
      }
    })
  }
  setTimeout(connect, 200)

  client.on('message', (value: socket.LocalSocketMessageInfo) => {
    try {
      const decoded = decodeSocketChunk(messageBuffer, value.message)
      messageBuffer = decoded.rest
      for (const rawMessage of decoded.messages) {
        const msg = parseVpnBridgeMessage(rawMessage)
        if (msg.type === KERNEL_MESSAGE_RUNTIME_TOPOLOGY) {
          callbacks.onTopology(msg.data as RuntimeAggregateState)
        } else if (msg.type === KERNEL_MESSAGE_TRAFFIC_STATS) {
          callbacks.onTrafficStats(msg.data as TrafficStatsPayload)
        } else if (msg.type === KERNEL_MESSAGE_RUNTIME_PEER_EVENT) {
          callbacks.onPeerEvent(msg.data as RuntimePeerEventPayload)
        } else if (msg.type === VPN_MESSAGE_LOGS) {
          callbacks.onLogs(msg.data as VpnLogData)
        }
      }
    } catch (e) {
      Logger.error('Failed to process VpnExtension message: ' + JSON.stringify(e), 'VpnExtensionSocketBridge')
    }
  })

  client.on('close', () => {
    callbacks.onDisconnected()
  })

  return client
}
