export const IGNORED_CONFIG_FIELDS: ReadonlySet<string> = new Set([
  'networking_method',
  'public_server_url',
  'advanced_settings',
  'dev_name',
  'mtu',
  'quic_listen_port',
  'bind_device',
  'enable_relay_network_whitelist',
  'enable_manual_routes',
  'instance_id',
  'credential_file',
  'acl',
  'ipv6_public_addr_prefix',
  'secure_mode',
  'socket_mark',
  // Core 已改用 vpn_portal_config（WireGuard 监听地址、私钥和命名客户端）。
  // 旧字段即使启用也会被最新 Core 拒绝，编辑页不再重复展示旧 VPN Portal。
  'enable_vpn_portal',
  'vpn_portal_listen_port',
  'vpn_portal_client_network_addr',
  'vpn_portal_client_network_len',
  // peer_urls 是当前面向用户的初始节点编辑入口；peers 是 Core 为公钥节点
  // 保留的结构化表示，不能再作为原始 JSON 重复暴露。
  'peers'
])

export const COMBINED_CONFIG_FIELDS: Record<string, string[]> = {
  basic_setting: ['virtual_ipv4_comp', 'hostname', 'identity'],
  algorithm_setting: ['data_compress_algo', 'encryption_algorithm'],
  virtual_ipv4_comp: ['dhcp', 'virtual_ip'],
  identity: ['network_name', 'network_secret'],
  vpn_portal: ['enable_vpn_portal', 'vpn_portal_listen_port', 'vpn_portal_client_network'],
  socks5: ['enable_socks5', 'socks5_port'],
  virtual_ip: ['virtual_ipv4', 'network_length'],
  vpn_portal_client_network: ['vpn_portal_client_network_addr', 'vpn_portal_client_network_len']
}

export function getCombinedConfigChildren(fieldName: string): string[] {
  return COMBINED_CONFIG_FIELDS[fieldName] ?? []
}
