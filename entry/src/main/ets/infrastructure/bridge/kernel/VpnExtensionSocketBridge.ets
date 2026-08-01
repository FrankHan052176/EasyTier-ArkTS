import { socket } from '@kit.NetworkKit'
import { Logger } from '../../../shared/logging/Logger'
import { RuntimeAggregateState } from '../../../types/runtime/RuntimeTypes'
import {
  KERNEL_MESSAGE_RUNTIME_PEER_EVENT,
  KERNEL_MESSAGE_RUNTIME_TOPOLOGY,
  KERNEL_MESSAGE_TRAFFIC_STATS,
  RuntimePeerEventPayload,
  TrafficStatsPayload,
  VpnRuntimeStartResultData,
  VpnLogData,
  VPN_MESSAGE_LOGS,
  VPN_MESSAGE_RUNTIME_START_RESULT
} from './KernelBridgeTypes'
import { decodeSocketChunk, parseVpnBridgeMessage } from './SocketCodec'

export interface VpnExtensionSocketBridgeCallbacks {
  isExtMode: () => boolean
  getSocketPath: (socketName: string) => string
  onConnected: () => void
  onDisconnected: () => void
  onReconnectRequested: () => void
  onTopology: (snapshot: RuntimeAggregateState) => void
  onTrafficStats: (stats: TrafficStatsPayload) => void
  onPeerEvent: (event: RuntimePeerEventPayload) => void
  onLogs: (logs: VpnLogData) => void
  onRuntimeStartResult: (result: VpnRuntimeStartResultData) => void
}

export function connectVpnExtensionSocket(
  socketName: string,
  currentClient: socket.LocalSocket | undefined,
  callbacks: VpnExtensionSocketBridgeCallbacks
): socket.LocalSocket {
  try {
    currentClient?.close()
  } catch (error) {
    Logger.debug(`closing stale VpnExtension socket failed: ${JSON.stringify(error)}`, 'VpnExtensionSocketBridge')
  }
  const client = socket.constructLocalSocketInstance()
  let messageBuffer = ''
  const address: socket.LocalConnectOptions = {
    address: {
      address: callbacks.getSocketPath(socketName)
    }
  }

  let reconnectRequested = false
  const connect = () => {
    if (!callbacks.isExtMode()) {
      return
    }
    client.connect(address).then(() => {
      Logger.debug('Connected to VpnExtension socket', 'VpnExtensionSocketBridge')
      callbacks.onConnected()
    }).catch((err: object) => {
      Logger.debug(`VpnExtension socket connect failed path=${address.address.address} error=${JSON.stringify(err)}`,
        'VpnExtensionSocketBridge')
      callbacks.onDisconnected()
      if (!reconnectRequested && callbacks.isExtMode()) {
        reconnectRequested = true
        callbacks.onReconnectRequested()
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
        } else if (msg.type === VPN_MESSAGE_RUNTIME_START_RESULT) {
          callbacks.onRuntimeStartResult(msg.data as VpnRuntimeStartResultData)
        }
      }
    } catch (e) {
      Logger.error('Failed to process VpnExtension message: ' + JSON.stringify(e), 'VpnExtensionSocketBridge')
    }
  })

  client.on('close', () => {
    callbacks.onDisconnected()
    if (!reconnectRequested && callbacks.isExtMode()) {
      reconnectRequested = true
      callbacks.onReconnectRequested()
    }
  })

  return client
}
