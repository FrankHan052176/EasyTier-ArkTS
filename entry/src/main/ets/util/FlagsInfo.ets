export function flagsCategory(flag: string): string {
  switch (flag) {
    case "latency_first": return "PERFORM"
    case "use_smoltcp": return "SYSTEM"
    case "disable_ipv6": return "NETWORK"
    case "enable_kcp_proxy": return "FEATURE"
    case "disable_kcp_input": return "FEATURE"
    case "disable_p2p": return "NETWORK"
    case "no_tun": return "SYSTEM"
    case "enable_exit_node": return "FEATURE"
    case "relay_all_peer_rpc": return "FEATURE"
    case "multi_thread": return "SYSTEM"
    case "proxy_forward_by_system": return "SYSTEM"
    case "disable_encryption": return "SECURITY"
    case "disable_udp_hole_punching": return "NETWORK"
    case "enable_magic_dns": return "DNS"
    case "enable_private_mode": return "SECURITY"
    case "enable_quic_proxy": return "FEATURE"
    case "disable_quic_input": return "FEATURE"
    case "disable_sym_hole_punching": return "NETWORK"
    case "p2p_only": return "NETWORK"
    default: return "OTHERS"
  }
}

export function flagsSymbol(flag: string): Resource {
  switch (flag) {
    case "latency_first": return $r("sys.symbol.network_acceleration")
    case "use_smoltcp": return $r("sys.symbol.square_grid_2x2")
    case "disable_ipv6": return $r("sys.symbol.link_slash")
    case "enable_kcp_proxy": return $r("sys.symbol.connection")
    case "disable_kcp_input": return $r("sys.symbol.link_slash")
    case "disable_p2p": return $r("sys.symbol.link_slash")
    case "no_tun": return $r("sys.symbol.arrow_up_to_line_slash")
    case "enable_exit_node": return $r("sys.symbol.leave_home_fill")
    case "relay_all_peer_rpc": return $r("sys.symbol.discover_fill")
    case "multi_thread": return $r("sys.symbol.fast")
    case "proxy_forward_by_system": return $r("sys.symbol.worldclock")
    case "disable_encryption": return $r("sys.symbol.lock_open")
    case "disable_udp_hole_punching": return $r("sys.symbol.link_slash")
    case "enable_magic_dns": return $r("sys.symbol.info_shield")
    case "enable_private_mode": return $r("sys.symbol.key_shield")
    case "enable_quic_proxy": return $r("sys.symbol.connection")
    case "disable_quic_input": return $r("sys.symbol.link_slash")
    case "disable_sym_hole_punching": return $r("sys.symbol.link_slash")
    case "p2p_only": return $r("sys.symbol.point_bottomleft_forward_to_point_topright_scurvepath")
    default: return $r("sys.symbol.questionmark_circle")
  }
}