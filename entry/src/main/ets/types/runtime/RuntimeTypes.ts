export enum NatTypeValue {
  Unknown = 0,
  OpenInternet = 1,
  NoPAT = 2,
  FullCone = 3,
  Restricted = 4,
  PortRestricted = 5,
  Symmetric = 6,
  SymUdpFirewall = 7,
  SymmetricEasyInc = 8,
  SymmetricEasyDec = 9,
}

export function natTypeToText(value: NatTypeValue): string {
  switch (value) {
    case NatTypeValue.OpenInternet:
      return '公网'
    case NatTypeValue.NoPAT:
      return '无端口转换'
    case NatTypeValue.FullCone:
      return '全锥型'
    case NatTypeValue.Restricted:
      return '受限锥型'
    case NatTypeValue.PortRestricted:
      return '端口受限型'
    case NatTypeValue.Symmetric:
      return '对称型'
    case NatTypeValue.SymUdpFirewall:
      return '对称防火墙'
    case NatTypeValue.SymmetricEasyInc:
      return '对称递增型'
    case NatTypeValue.SymmetricEasyDec:
      return '对称递减型'
    default:
      return '未知'
  }
}

export interface RuntimeRouteView {
  peerId: number
  hostname?: string
  ipv4?: string
  ipv4Cidr?: string
  ipv6Cidr?: string
  proxyCidrs: string[]
  nextHopPeerId?: number
  cost?: number
  pathLatency?: number
}

export interface RuntimePeerConnStats {
  rxBytes: number
  txBytes: number
  latencyUs: number
}

export interface RuntimePeerConnInfo {
  connId?: string
  myPeerId?: number
  peerId?: number
  features?: string[]
  tunnelType?: string
  localAddr?: string
  remoteAddr?: string
  resolvedRemoteAddr?: string
  lossRate?: number
  stats?: RuntimePeerConnStats
  isClient?: boolean
  networkName?: string
  isClosed?: boolean
  secureAuthLevel?: number
  peerIdentityType?: number
}

export interface RuntimePeerInfo {
  peerId: number
  defaultConnId?: string
  directlyConnectedConns?: string[]
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
