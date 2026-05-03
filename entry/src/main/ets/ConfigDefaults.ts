import { ConfigJson } from './SchemaConfig'

export function getDefaultConfig(hostname: string): ConfigJson {
  const cfg = JSON.parse('{}') as ConfigJson
  cfg.networking_method = 1
  cfg.public_server_url = ''
  cfg.enable_relay_network_whitelist = true
  cfg.enable_manual_routes = true
  cfg.dhcp = true
  cfg.virtual_ipv4 = '10.0.0.1'
  cfg.network_length = 24
  cfg.hostname = hostname
  cfg.network_name = 'easytier'
  cfg.network_secret = ''
  cfg.multi_thread = true
  cfg.vpn_portal_listen_port = 22022
  cfg.vpn_portal_client_network_addr = '10.0.1.0'
  cfg.vpn_portal_client_network_len = 24
  cfg.socks5_port = 1080
  return cfg
}
