export interface NetworkInstanceRunningInfo {
  dev_name: string
  my_node_info: NodeInfo
  events: Array<string>,
  routes: Route[]
  peers: PeerInfo[]
  peer_route_pairs: PeerRoutePair[]
  running: boolean
  error_msg?: string
}
@ObservedV2
export class NetworkInstanceRunningInfoWithUnwrappedEvents {
  dev_name: string = ""
  my_node_info: NodeInfo = {
    virtual_ipv4: {
      address: {
        addr: 0
      },
      network_length: 0
    },
    hostname: "",
    version: "",
    ips: {
      public_ipv4: {
        addr: 0
      },
      public_ipv6: {
        part1: 0,
        part2: 0,
        part3: 0,
        part4: 0
      },
      interface_ipv4s: [],
      interface_ipv6s: [],
      listeners: []
    },
    stun_info: {
      udp_nat_type: 0,
      tcp_nat_type: 0,
      last_update_time: 0
    },
    listeners: [],
    vpn_portal_cfg: undefined
  }
  @Trace events: Array<Event> = []
  @Trace routes: Route[] = []
  @Trace peers: PeerInfo[] = []
  @Trace peer_route_pairs: PeerRoutePair[] = []
  @Trace running: boolean = false
  @Trace error_msg?: string
}

export interface Event {
  time: string
  type: string
  msg: string
}

export interface Ipv4Addr {
  addr: number
}

export interface Ipv4Inet {
  address: Ipv4Addr
  network_length: number
}

export interface Ipv6Addr {
  part1: number
  part2: number
  part3: number
  part4: number
}

export interface Url {
  url: string
}

export interface Listener {
  serialization: string;
  scheme_end: number;
  username_end: number;
  host_start: number;
  host_end: number;
  host: string;
  port?: number;
  path_start: number;
  query_start?: number;
  fragment_start?: number;
}

export interface IPInfo {
  public_ipv4: Ipv4Addr;
  interface_ipv4s: Ipv4Addr[];
  public_ipv6: Ipv6Addr;
  interface_ipv6s: Ipv6Addr[];
  listeners: Listener[];
}

export interface NodeInfo {
  virtual_ipv4: Ipv4Inet,
  hostname: string
  version: string
  ips: IPInfo
  stun_info: StunInfo
  listeners: Url[]
  vpn_portal_cfg?: string
}

export interface StunInfo {
  udp_nat_type: number
  tcp_nat_type: number
  last_update_time: number
}

export interface Route {
  peer_id: number
  ipv4_addr: Ipv4Inet | null
  next_hop_peer_id: number
  cost: number
  proxy_cidrs: string[]
  hostname: string
  stun_info?: StunInfo
  inst_id: string
  version: string
}

export interface PeerInfo {
  peer_id: number
  conns: PeerConnInfo[]
}

export interface PeerConnInfo {
  conn_id: string
  my_peer_id: number
  is_client: boolean
  peer_id: number
  features: string[]
  tunnel?: TunnelInfo
  stats?: PeerConnStats
  loss_rate: number
}

export interface PeerRoutePair {
  route: Route
  peer?: PeerInfo
}

export interface TunnelInfo {
  tunnel_type: string
  local_addr: string
  remote_addr: string
}

export interface PeerConnStats {
  rx_bytes: number
  tx_bytes: number
  rx_packets: number
  tx_packets: number
  latency_us: number
}
