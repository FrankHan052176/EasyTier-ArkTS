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
  'socket_mark'
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
