import { getHostname } from "../Conversion";
import { util } from "@kit.ArkTS";

@ObservedV2
export class network_identity {
  @Trace network_name: string = "easytier";
  @Trace network_secret: string = "";
}
@ObservedV2
export class peer {
  @Trace uri: string  = "tcp://public.easytier.top:11010";
}
@ObservedV2
export class proxy_network {
  @Trace cidr: string  = "";
}
@ObservedV2
export class vpn_portal_config {
  @Trace client_cidr: string = "";
  @Trace wireguard_listen: string = "";
}
@ObservedV2
export class port_forwards {
  @Trace bind_addr: string = "";
  @Trace dst_addr: string = "";
  @Trace proto: string = "";
}
@ObservedV2
export class flags {
  @Trace accept_dns: boolean = false;
  @Trace dev_name: string | null = null;
  @Trace disable_kcp_input: boolean = false;
  @Trace disable_p2p: boolean = false;
  @Trace disable_quic_input: boolean = false;
  @Trace disable_udp_hole_punching: boolean = false;
  @Trace enable_encryption: boolean = false;
  @Trace enable_exit_node: boolean = false;
  @Trace enable_ipv6: boolean = true;
  @Trace enable_kcp_proxy: boolean = false;
  @Trace enable_quic_proxy: boolean = false;
  @Trace latency_first: boolean = false;
  @Trace no_tun: boolean = false;
  @Trace private_mode: boolean = false;
  @Trace proxy_forward_by_system: boolean = false;
  @Trace relay_all_peer_rpc: boolean = false;
  @Trace relay_network_whitelist: string = "";
  @Trace use_smoltcp: boolean = false;
}
@ObservedV2
export class Config {
  @Trace hostname: string = getHostname();
  @Trace instance_id: string = util.generateRandomUUID(true);
  @Trace instance_name: string = this.instance_id.substring(0, 8);
  @Trace dhcp: boolean = true;
  @Trace listeners: string[] = [];
  @Trace mapped_listeners: string[] = [];
  @Trace exit_nodes: string[] = [];
  @Trace rpc_portal: string = "";
  @Trace rpc_portal_whitelist: string[] = [];
  @Trace routes: string[] = [];
  @Trace socks5_proxy : string = "";
  @Trace network_identity: network_identity = new network_identity();
  @Trace peers: peer[] = [new peer()];
  @Trace proxy_networks: proxy_network[] = [];
  @Trace vpn_portal_config: vpn_portal_config | null = null;
  @Trace port_forwards: port_forwards[] = [];
  @Trace flags: flags = new flags();
}