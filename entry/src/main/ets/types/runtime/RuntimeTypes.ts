export enum NatTypeValue {
  Unknown = 0,
}

export interface RuntimeRouteView {
  peerId: number
  hostname?: string
  ipv4?: string
  ipv4Cidr?: string
  ipv6Cidr?: string
  proxyCidrs: string[]
  cost?: number
}

export interface RuntimePeerConnStats {
  rxBytes: number
  txBytes: number
  latencyUs: number
}

export interface RuntimePeerConnInfo {
  tunnelType?: string
  lossRate?: number
  stats?: RuntimePeerConnStats
}

export interface RuntimePeerInfo {
  peerId: number
  conns: RuntimePeerConnInfo[]
}

export interface RuntimeMyNodeInfo {
  virtualIpv4?: string
  virtualIpv4Cidr?: string
  udpNatType?: NatTypeValue
  tcpNatType?: NatTypeValue
}

export interface RuntimeInstanceState {
  configId: string
  instanceId: string
  displayName: string
  running: boolean
  tunRequired: boolean
  tunAttached: boolean
  magicDnsEnabled: boolean
  needExitNode: boolean
  myNodeInfo?: RuntimeMyNodeInfo
  routes: RuntimeRouteView[]
  peers: RuntimePeerInfo[]
}

export interface RuntimeTunState {
  active: boolean
  attachedInstanceIds: string[]
  aggregatedRoutes: string[]
}

export interface RuntimeAggregateState {
  instances: RuntimeInstanceState[]
  tun: RuntimeTunState
}
