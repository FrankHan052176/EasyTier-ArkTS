import { RuntimeAggregateState } from '../runtime/RuntimeTypes'
import { RuntimePeerEventPayload, TrafficStatsPayload } from '../../infrastructure/bridge/kernel/KernelBridgeTypes'

export const ENTRY_SYNC_CONTINUATION_SOCKET_EVENT = 'entry_sync_continuation_socket'
export const START_BACKGROUND_EVENT = 'start_bg'
export const STOP_BACKGROUND_EVENT = 'stop_bg'
export const SETUP_TUN_EVENT = 'setup_tun'
export const CHANGE_IPV4_EVENT = 'change_ipv4'
export const UPDATE_COLOR_MODE_EVENT = 'update_color_mode'
export const KERNEL_RUNTIME_TOPOLOGY_EVENT = 'kernel_runtime_topology'
export const KERNEL_RUNTIME_PEER_EVENT = 'kernel_runtime_peer_event'
export const KERNEL_TRAFFIC_STATS_EVENT = 'kernel_traffic_stats'

export interface StartBackgroundEventPayload {
  cfg: string
  uuid?: string
  name: string
}

export interface TunSetupEventPayload {
  ip: string
  mask: number
  magicDNS: boolean
  id: string
  needExitNode: boolean
  routes?: string[]
}

export interface KernelRuntimeTopologyEventPayload {
  snapshot: RuntimeAggregateState
}

export interface KernelRuntimePeerEventPayload {
  peerEvent: RuntimePeerEventPayload
}

export interface KernelTrafficStatsEventPayload {
  stats: TrafficStatsPayload
}
