import {
  RuntimeAggregateState,
  RuntimePeerConnInfo
} from '../../../types/runtime/RuntimeTypes'

export const KERNEL_SOCKET_NAME = 'easytier-kernel.sock'
export const KERNEL_MESSAGE_RUNTIME_TOPOLOGY = 'runtime_topology'
export const KERNEL_MESSAGE_RUNTIME_PEER_EVENT = 'runtime_peer_event'
export const KERNEL_MESSAGE_TRAFFIC_STATS = 'traffic_stats'
export const KERNEL_MESSAGE_TUN_REQUEST = 'tun_request'
export const VPN_MESSAGE_LOGS = 'logs'
export const VPN_MESSAGE_CONTINUE_STATE = 'continue_state'
export const VPN_MESSAGE_RUNTIME_START_REQUEST = 'runtime_start_request'
export const VPN_MESSAGE_RUNTIME_START_RESULT = 'runtime_start_result'

export type KernelSocketMessageType = 'runtime_topology' | 'runtime_peer_event' | 'traffic_stats' | 'tun_request'
export type VpnBridgeMessageType = KernelSocketMessageType | 'logs' | 'continue_state' | 'runtime_start_request' |
  'runtime_start_result'

export interface KernelSocketMessage {
  messageType: KernelSocketMessageType | string
  payloadJson: string | Object
}

export interface TunRequestPayload {
  configId: string
  instanceId: string
  displayName: string
  virtualIpv4?: string
  virtualIpv4Cidr?: string
  aggregatedRoutes: string[]
  magicDnsEnabled: boolean
  needExitNode: boolean
}

export interface VpnLogData {
  logs: string[]
}

export interface PeerTrafficStats {
  peerId: number
  rxBytes: number
  txBytes: number
  totalBytes: number
  latencyUs: number
  lossRate: number
}

export interface InstanceTrafficStats {
  configId: string
  instanceId: string
  rxBytes: number
  txBytes: number
  peers: PeerTrafficStats[]
}

export interface TrafficStatsPayload {
  instances: InstanceTrafficStats[]
}

export type RuntimePeerEventName = 'peer_added' | 'peer_removed' | 'peer_conn_added' | 'peer_conn_removed'

export interface RuntimePeerEventPayload {
  event: RuntimePeerEventName
  configId: string
  instanceId: string
  peerId: number
  conn?: RuntimePeerConnInfo
}

export interface VpnContinueStateData {
  active: boolean
}

export interface VpnRuntimeStartRequestData {
  instanceId: string
  cfg: string
  name: string
  socketFilesDir: string
  vpnRoutes: boolean
  whiteList: boolean
  blackList: string[]
  dns: string
  dev: boolean
  forceGlobal: boolean
  coreLog: boolean
  debugLog: boolean
}

export interface VpnRuntimeStartResultData {
  instanceId: string
  started: boolean
  error?: string
}

export interface VpnMessage {
  type: VpnBridgeMessageType | string
  data: RuntimeAggregateState | VpnLogData | TrafficStatsPayload | RuntimePeerEventPayload |
    VpnContinueStateData | VpnRuntimeStartRequestData | VpnRuntimeStartResultData
}
