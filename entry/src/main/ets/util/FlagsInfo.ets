export function flagsCategory(flag: string): string {
  switch (flag) {
    case "disable_encryption":
    case "enable_private_mode":
      return "SECURITY"
    case "use_smoltcp":
    case "multi_thread":
    case "proxy_forward_by_system":
    case "no_tun":
      return "SYSTEM"
    case "disable_upnp":
    case "disable_relay_data":
    case "enable_kcp_proxy":
    case "disable_kcp_input":
    case "enable_exit_node":
    case "relay_all_peer_rpc":
    case "enable_quic_proxy":
      return "FEATURE"
    case "ipv6_public_addr_provider":
    case "ipv6_public_addr_auto":
    case "need_p2p":
    case "lazy_p2p":
    case "disable_tcp_hole_punching":
    case "disable_quic_input":
    case "disable_udp_hole_punching":
    case "disable_ipv6":
    case "disable_p2p":
    case "disable_sym_hole_punching":
    case "p2p_only":
      return "NETWORK"
    case "enable_magic_dns":
      return "DNS"
    case "latency_first":
      return "PERFORM"
    default:
      return "OTHERS"
  }
}

export function flagsSymbol(flag: string): Resource {
  switch (flag) {
    case "latency_first":
      return $r("sys.symbol.network_acceleration")
    case "use_smoltcp":
      return $r("sys.symbol.square_grid_2x2")
    case "enable_kcp_proxy":
      return $r("sys.symbol.connection")
    case "no_tun":
      return $r("sys.symbol.arrow_up_to_line_slash")
    case "enable_exit_node":
      return $r("sys.symbol.arrow_up_circle")
    case "relay_all_peer_rpc":
      return $r("sys.symbol.discover_fill")
    case "multi_thread":
      return $r("sys.symbol.fast")
    case "need_p2p":
    case "ipv6_public_addr_provider":
    case "ipv6_public_addr_auto":
    case "proxy_forward_by_system":
      return $r("sys.symbol.worldclock")
    case "disable_encryption":
      return $r("sys.symbol.lock_open")
    case "enable_magic_dns":
      return $r("sys.symbol.info_shield")
    case "enable_private_mode":
      return $r("sys.symbol.key_shield")
    case "enable_quic_proxy":
      return $r("sys.symbol.connection")
    case "disable_tcp_hole_punching":
    case "disable_upnp":
    case "disable_relay_data":
    case "disable_kcp_input":
    case "disable_p2p":
    case "disable_ipv6":
    case "disable_udp_hole_punching":
    case "disable_quic_input":
    case "disable_sym_hole_punching":
      return $r("sys.symbol.link_slash")
    case "lazy_p2p":
    case "p2p_only":
      return $r("sys.symbol.point_bottomleft_forward_to_point_topright_scurvepath")
    default:
      return $r("sys.symbol.questionmark_circle")
  }
}