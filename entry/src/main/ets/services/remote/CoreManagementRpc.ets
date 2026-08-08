import { JSON } from '@kit.ArkTS'
import easytier from 'easytier-ohrs'
import { ConfigJson } from '../../config/schema/SchemaConfig'
import {
  RuntimeInstanceState,
  RuntimeMyNodeInfo,
  RuntimePeerConnInfo,
  RuntimePeerConnStats,
  RuntimePeerInfo,
  RuntimeRouteView
} from '../../types/runtime/RuntimeTypes'

const WEB_CLIENT_SERVICE = 'api.manage.WebClientService'
const CONFIG_SOURCE_USER = 'ConfigSourceUser'

interface CoreRpcEnvelope<T> {
  ok: boolean
  result?: T
  error?: string
}

export interface CoreUuid {
  part1: number
  part2: number
  part3: number
  part4: number
}

interface EmptyRequest {
}

interface ListNetworkInstanceResponse {
  inst_ids?: CoreUuid[]
}

export interface CoreNetworkMeta {
  inst_id?: CoreUuid
  network_name?: string
  config_permission?: number
  instance_name?: string
  source?: string
}

interface ListNetworkInstanceMetaRequest {
  inst_ids: CoreUuid[]
}

interface ListNetworkInstanceMetaResponse {
  metas?: CoreNetworkMeta[]
}

interface CollectNetworkInfoRequest {
  inst_ids: CoreUuid[]
}

interface CoreIpv4Address {
  addr?: number
}

interface CoreIpv4Inet {
  address?: CoreIpv4Address
  network_length?: number
}

interface CoreStunInfo {
  udp_nat_type?: number
  tcp_nat_type?: number
}

interface CoreNodeInfo {
  virtual_ipv4?: CoreIpv4Inet
  hostname?: string
  version?: string
  stun_info?: CoreStunInfo
}

interface CoreUrl {
  url?: string
}

interface CoreTunnelInfo {
  tunnel_type?: string
  local_addr?: CoreUrl
  remote_addr?: CoreUrl
  resolved_remote_addr?: CoreUrl
}

interface CorePeerConnStats {
  rx_bytes?: number | string
  tx_bytes?: number | string
  latency_us?: number | string
}

interface CorePeerConnInfo {
  conn_id?: string
  my_peer_id?: number
  peer_id?: number
  features?: string[]
  tunnel?: CoreTunnelInfo
  stats?: CorePeerConnStats
  loss_rate?: number | string
  is_client?: boolean
  network_name?: string
  is_closed?: boolean
  secure_auth_level?: number
  peer_identity_type?: number
}

interface CorePeerInfo {
  peer_id?: number
  conns?: CorePeerConnInfo[]
  default_conn_id?: CoreUuid
  directly_connected_conns?: CoreUuid[]
}

interface CoreRoute {
  peer_id?: number
  ipv4_addr?: CoreIpv4Inet
  next_hop_peer_id?: number
  cost?: number
  path_latency?: number
  proxy_cidrs?: string[]
  hostname?: string
}

export interface CoreNetworkInstanceRunningInfo {
  dev_name?: string
  my_node_info?: CoreNodeInfo
  events?: string[]
  routes?: CoreRoute[]
  peers?: CorePeerInfo[]
  running?: boolean
  error_msg?: string
}

interface CoreRunningInfoMap {
  map?: Record<string, CoreNetworkInstanceRunningInfo>
}

interface CollectNetworkInfoResponse {
  info?: CoreRunningInfoMap
}

interface GetNetworkInstanceConfigRequest {
  inst_id: CoreUuid
}

interface GetNetworkInstanceConfigResponse {
  config?: ConfigJson
  source?: string
}

interface RunNetworkInstanceRequest {
  inst_id: CoreUuid
  config: ConfigJson
  overwrite: boolean
  source: string
}

interface RunNetworkInstanceResponse {
  inst_id?: CoreUuid
}

interface DeleteNetworkInstanceRequest {
  inst_ids: CoreUuid[]
}

interface DeleteNetworkInstanceResponse {
  remain_inst_ids?: CoreUuid[]
}

interface ValidateConfigRequest {
  config: ConfigJson
}

interface ValidateConfigResponse {
  toml_config?: string
}

function padHex(value: number): string {
  return (value >>> 0).toString(16).padStart(8, '0')
}

export function coreUuidToString(value: CoreUuid): string {
  const part1 = padHex(value.part1)
  const part2 = padHex(value.part2)
  const part3 = padHex(value.part3)
  const part4 = padHex(value.part4)
  return `${part1}-${part2.substring(0, 4)}-${part2.substring(4)}-${part3.substring(0, 4)}-${part3.substring(4)}${part4}`
}

export function coreUuidFromString(value: string): CoreUuid {
  const compact = value.trim().toLowerCase().replace(/-/g, '')
  if (!/^[0-9a-f]{32}$/.test(compact)) {
    throw new Error(`无效的 Core 实例 ID: ${value}`)
  }
  return {
    part1: Number.parseInt(compact.substring(0, 8), 16),
    part2: Number.parseInt(compact.substring(8, 16), 16),
    part3: Number.parseInt(compact.substring(16, 24), 16),
    part4: Number.parseInt(compact.substring(24, 32), 16)
  }
}

function numberValue(value: number | string | undefined): number {
  if (typeof value === 'number') {
    return Number.isFinite(value) ? value : 0
  }
  if (typeof value === 'string') {
    const parsed = Number(value)
    return Number.isFinite(parsed) ? parsed : 0
  }
  return 0
}

function ipv4Text(value: CoreIpv4Inet | undefined): string | undefined {
  const raw = value?.address?.addr
  if (raw === undefined) {
    return undefined
  }
  const address = raw >>> 0
  return `${(address >>> 24) & 0xFF}.${(address >>> 16) & 0xFF}.${(address >>> 8) & 0xFF}.${address & 0xFF}`
}

function mapNodeInfo(info: CoreNetworkInstanceRunningInfo | undefined): RuntimeMyNodeInfo | undefined {
  const source = info?.my_node_info
  if (!source) {
    return undefined
  }
  const virtualIpv4 = ipv4Text(source.virtual_ipv4)
  const networkLength = source.virtual_ipv4?.network_length
  return {
    virtualIpv4,
    virtualIpv4Cidr: virtualIpv4 && networkLength !== undefined ? `${virtualIpv4}/${networkLength}` : virtualIpv4,
    udpNatType: source.stun_info?.udp_nat_type,
    tcpNatType: source.stun_info?.tcp_nat_type
  }
}

function mapRoute(route: CoreRoute): RuntimeRouteView {
  const ipv4 = ipv4Text(route.ipv4_addr)
  const networkLength = route.ipv4_addr?.network_length
  return {
    peerId: route.peer_id ?? 0,
    hostname: route.hostname,
    ipv4,
    ipv4Cidr: ipv4 && networkLength !== undefined ? `${ipv4}/${networkLength}` : ipv4,
    proxyCidrs: route.proxy_cidrs ?? [],
    nextHopPeerId: route.next_hop_peer_id,
    cost: route.cost,
    pathLatency: route.path_latency
  }
}

function mapPeerStats(stats: CorePeerConnStats | undefined): RuntimePeerConnStats | undefined {
  if (!stats) {
    return undefined
  }
  return {
    rxBytes: numberValue(stats.rx_bytes),
    txBytes: numberValue(stats.tx_bytes),
    latencyUs: numberValue(stats.latency_us)
  }
}

function mapPeerConnection(connection: CorePeerConnInfo): RuntimePeerConnInfo {
  return {
    connId: connection.conn_id,
    myPeerId: connection.my_peer_id,
    peerId: connection.peer_id,
    features: connection.features ?? [],
    tunnelType: connection.tunnel?.tunnel_type,
    localAddr: connection.tunnel?.local_addr?.url,
    remoteAddr: connection.tunnel?.remote_addr?.url,
    resolvedRemoteAddr: connection.tunnel?.resolved_remote_addr?.url,
    lossRate: numberValue(connection.loss_rate),
    stats: mapPeerStats(connection.stats),
    isClient: connection.is_client,
    networkName: connection.network_name,
    isClosed: connection.is_closed,
    secureAuthLevel: connection.secure_auth_level,
    peerIdentityType: connection.peer_identity_type
  }
}

function mapPeer(peer: CorePeerInfo): RuntimePeerInfo {
  return {
    peerId: peer.peer_id ?? 0,
    defaultConnId: peer.default_conn_id ? coreUuidToString(peer.default_conn_id) : undefined,
    directlyConnectedConns: (peer.directly_connected_conns ?? []).map((id: CoreUuid) => coreUuidToString(id)),
    conns: (peer.conns ?? []).map((connection: CorePeerConnInfo) => mapPeerConnection(connection))
  }
}

export function mapCoreRuntimeInstance(instanceId: string, displayName: string, config: ConfigJson | undefined,
  info: CoreNetworkInstanceRunningInfo | undefined): RuntimeInstanceState {
  const noTun = Boolean(config?.no_tun)
  const exitNodes = config?.exit_nodes as string[] | undefined
  return {
    configId: instanceId,
    instanceId,
    displayName,
    running: info?.running ?? false,
    tunRequired: !noTun,
    tunAttached: false,
    magicDnsEnabled: Boolean(config?.enable_magic_dns),
    needExitNode: (exitNodes?.length ?? 0) > 0,
    myNodeInfo: mapNodeInfo(info),
    routes: (info?.routes ?? []).map((route: CoreRoute) => mapRoute(route)),
    peers: (info?.peers ?? []).map((peer: CorePeerInfo) => mapPeer(peer))
  }
}

export class CoreManagementRpcClient {
  private sessionKey: string

  constructor(sessionKey: string) {
    this.sessionKey = sessionKey
  }

  async listInstanceIds(): Promise<CoreUuid[]> {
    const request: EmptyRequest = {}
    const response = await this.call<ListNetworkInstanceResponse>('ListNetworkInstance', request)
    return response.inst_ids ?? []
  }

  async listInstanceMetas(ids: CoreUuid[]): Promise<CoreNetworkMeta[]> {
    const request: ListNetworkInstanceMetaRequest = { inst_ids: ids }
    const response = await this.call<ListNetworkInstanceMetaResponse>('ListNetworkInstanceMeta', request)
    return response.metas ?? []
  }

  async collectNetworkInfo(ids: CoreUuid[]): Promise<Record<string, CoreNetworkInstanceRunningInfo>> {
    const request: CollectNetworkInfoRequest = { inst_ids: ids }
    const response = await this.call<CollectNetworkInfoResponse>('CollectNetworkInfo', request)
    return response.info?.map ?? {}
  }

  async getNetworkConfig(instanceId: string): Promise<ConfigJson | undefined> {
    const request: GetNetworkInstanceConfigRequest = { inst_id: coreUuidFromString(instanceId) }
    const response = await this.call<GetNetworkInstanceConfigResponse>('GetNetworkInstanceConfig', request)
    return response.config
  }

  async runNetworkConfig(instanceId: string, config: ConfigJson): Promise<boolean> {
    const request: RunNetworkInstanceRequest = {
      inst_id: coreUuidFromString(instanceId),
      config,
      overwrite: false,
      source: CONFIG_SOURCE_USER
    }
    const response = await this.call<RunNetworkInstanceResponse>('RunNetworkInstance', request)
    return response.inst_id !== undefined
  }

  async deleteNetworkInstance(instanceId: string): Promise<boolean> {
    const request: DeleteNetworkInstanceRequest = { inst_ids: [coreUuidFromString(instanceId)] }
    const response = await this.call<DeleteNetworkInstanceResponse>('DeleteNetworkInstance', request)
    const remaining = response.remain_inst_ids ?? []
    return !remaining.some((id: CoreUuid) => coreUuidToString(id) === instanceId)
  }

  async validateNetworkConfig(config: ConfigJson): Promise<string | undefined> {
    const request: ValidateConfigRequest = { config }
    const response = await this.call<ValidateConfigResponse>('ValidateConfig', request)
    return response.toml_config
  }

  private async call<T>(methodName: string, payload: Object): Promise<T> {
    const raw = await easytier.callNearbyManagementJsonRpc(
      this.sessionKey,
      WEB_CLIENT_SERVICE,
      methodName,
      undefined,
      JSON.stringify(payload)
    )
    let envelope: CoreRpcEnvelope<T>
    try {
      envelope = JSON.parse(raw) as CoreRpcEnvelope<T>
    } catch (_) {
      throw new Error('Core 管理 RPC 返回了无效 JSON')
    }
    if (!envelope.ok) {
      throw new Error(envelope.error ?? `Core 管理 RPC 调用失败: ${methodName}`)
    }
    if (envelope.result === undefined) {
      throw new Error(`Core 管理 RPC 响应为空: ${methodName}`)
    }
    return envelope.result
  }
}
