import { RuntimeAggregateState } from '../../../types/runtime/RuntimeTypes'

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

export interface VpnContinueStateData {
  active: boolean
}

export interface VpnSnapshotSubscriptionData {
  enabled: boolean
}

export interface VpnMessage {
  type: string
  data: RuntimeAggregateState | VpnLogData | VpnContinueStateData | VpnSnapshotSubscriptionData
}
