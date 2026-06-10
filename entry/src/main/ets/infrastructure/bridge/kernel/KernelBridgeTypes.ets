import {
  RuntimeAggregateState,
  RuntimePeerConnInfo
} from '../../../types/runtime/RuntimeTypes'

export const KERNEL_SOCKET_NAME = 'easytier-kernel.sock'

export interface KernelSocketMessage {
  messageType: string
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

export interface VpnMessage {
  type: string
  data: RuntimeAggregateState | VpnLogData | TrafficStatsPayload | RuntimePeerEventPayload | VpnContinueStateData
}
