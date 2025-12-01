import { getHostname, safeFieldName } from "./Conversion";
import { util } from "@kit.ArkTS";
import { SafeSet } from "./SafeSet";
import { Logger } from "./Logger";
import Manager from "../Manager";
import {
  compressedIP, compressedMask, compressedProtocol,
  uncompressedBoolean,
  uncompressedIP, uncompressedMask,
  uncompressedProtocol,
  valueType } from "./Compress";

@ObservedV2
export class network_identity {
  @Trace network_name: string = "easytier";
  @Trace network_secret: string = "";
  _config: Config | undefined
  constructor(config: Config | undefined = undefined) {
    if (config) {
      this._config = config
    }
  }
  @Monitor("network_name","network_secret")
  onConfigChange(monitor: IMonitor) {
    if (this._config && !this._config._disableUpdate) {
      Manager.updateConfig(this._config)
      monitor.dirty.forEach((path: string) => {
        Logger.debug(`${path} changed from ${monitor.value(path)?.before} to ${monitor.value(path)?.now}`)
      })
    }
  }
  toString(): string {
    return this.network_name+":"+this.network_secret
  }
  setName(name: string): network_identity {
    this.network_name = name
    return this
  }
  from(profile: network_identity): network_identity {
    this.network_name = ""+profile.network_name
    this.network_secret = ""+profile.network_secret
    return this
  }
  fromString(input: string): network_identity {
    let split = input.split(":")
    this.network_name = split[0]
    this.network_secret = split[1]
    return this
  }
  reset() {
    this.network_name = "easytier"
    this.network_secret = ""
  }
}
export enum Protocol {
  TCP = "tcp",
  TCP6 = "tcp6",
  UDP = "udp",
  UDP6 = "udp6",
  QUIC = "quic",
  QUIC6 = "quic6",
  WS = "ws",
  WS6 = "ws6",
  WSS = "wss",
  WSS6 = "wss6",
  WG = "wg",
  WG6 = "wg6",
  UNKNOWN = ""
}
export function convertToProtocol(input: string): Protocol {
  switch (input) {
    case "udp": return Protocol.UDP;
    case "udp6": return Protocol.UDP6;
    case "quic": return Protocol.QUIC;
    case "quic6": return Protocol.QUIC6;
    case "ws": return Protocol.WS;
    case "ws6": return Protocol.WS6;
    case "wss": return Protocol.WSS;
    case "wss6": return Protocol.WSS6;
    case "wg": return Protocol.WG;
    case "wg6": return Protocol.WG6;
    default : return Protocol.TCP;
  }
}
export function protocolColor(protocol:Protocol): ResourceColor {
  switch (protocol) {
    case Protocol.UDP: return "#ffd94838";
    case Protocol.QUIC: return "#ff800080";
    case Protocol.WS: return "#ff64bb5c";
    case Protocol.WSS: return "#ff5ba854";
    case Protocol.WG: return "#ffed6f21";
    default : return "#ff0a59f7";
  }
}
export function protocolBGColor(protocol:Protocol): ResourceColor {
  switch (protocol) {
    case Protocol.UDP: return "#33d94838";
    case Protocol.QUIC: return "#33800080";
    case Protocol.WS: return "#3364bb5c";
    case Protocol.WSS: return "#335ba854";
    case Protocol.WG: return "#33ed6f21";
    default : return "#330a59f7";
  }
}
@ObservedV2
export class peer {
  @Trace _protocol: Protocol = Protocol.TCP
  @Trace _domain: string = "public.easytier.top"
  @Trace _port: number = 11010
  setUri(uri: string): peer {
    let split = uri.split("://")
    this._protocol = convertToProtocol(split[0])
    this._domain = split[1].split(":")[0]
    this._port = Number.parseInt(split[1].split(":")[1])
    return this
  }
  from(peer: peer): peer {
    this._protocol = peer._protocol
    this._domain = peer._domain
    this._port = peer._port
    return this
  }
  toString(): string {
    return 'uri = "'+this._protocol+"://"+this._domain+":"+this._port+'"'
  }
  toShortString(): string {
    return this._protocol+"://"+this._domain+":"+this._port+'"'
  }
  toCompressedString(): string {
    return compressedProtocol(this._protocol)+this._domain+":"+this._port
  }
  fromCompressedString(input: string): peer {
    this._protocol = uncompressedProtocol(input.charAt(0))
    let split = input.substring(1).split(":")
    this._domain = split[0]
    this._port = Number.parseInt(split[1])
    return this
  }
  reset() {
    this._protocol = Protocol.TCP
    this._domain = "public.easytier.top"
    this._port = 11010
  }
}
@ObservedV2
export class SharedPeer extends peer {
  @Trace name: string
  @Trace description: string
  @Trace version: string
  @Trace allow_relay: boolean
  @Trace usage_percentage: number
  @Trace max_connections: number
  @Trace current_connections: number
  @Trace update: number = 0

  isEnabled(): boolean {
    if (this.update < 200) {
      return Manager.peers.has(this)
    }else return false
  }

  changeEnabled(update: boolean = true) {
    if (!Manager.peers.has(this)) {
      Manager.peers.add(this, update)
    }else {
      Manager.peers.delete(this, update)
    }
    this.update = (this.update+1)%100
  }

  constructor(obj: object) {
    super()
    super.setUri(obj["address"])
    this.name = obj["name"]
    this.description = obj["description"]
    this.version = obj["version"]
    this.allow_relay = obj["allow_relay"]
    this.usage_percentage = obj["usage_percentage"]
    this.max_connections = obj["max_connections"]
    this.current_connections = obj["current_connections"]
  }
  init(obj: object) {
    this.name = obj["name"]
    this.description = obj["description"]
    this.version = obj["version"]
    this.allow_relay = obj["allow_relay"]
    this.usage_percentage = obj["usage_percentage"]
    this.max_connections = obj["max_connections"]
    this.current_connections = obj["current_connections"]
  }
}
@ObservedV2
export class cidr {
  @Trace ipv4: string = "10.0.0.0"
  @Trace mask: number = 24
  toString(): string {
    return 'cidr = "'+this.ipv4+'/'+this.mask+'"'
  }
  toRawString(): string {
    return this.ipv4+'/'+this.mask
  }
  fromString(string:string): cidr {
    let split = string.split("/")
    this.ipv4 = split[0]
    this.mask = Number.parseInt(split[1])
    return this
  }
  from(network: cidr): cidr {
    this.ipv4 = network.ipv4
    this.mask = network.mask
    return this
  }
  reset() {
    this.ipv4 = "10.0.0.0"
    this.mask = 24
  }
  toCompressedString(): string {
    return compressedIP(this.ipv4)+compressedMask(this.mask)
  }
  fromCompressedString(input: string): cidr {
    this.ipv4 = uncompressedIP(input.substring(0,4))
    this.mask = uncompressedMask(input.charAt(4))
    return this
  }
}
@ObservedV2
export class route {
  @Trace ipv4: string = "127.0.0.0"
  @Trace mask: number = 0
  toString(): string {
    return this.ipv4+'/'+this.mask
  }
  from(network: route): route {
    this.ipv4 = network.ipv4
    this.mask = network.mask
    return this
  }
  fromString(string: string): route {
    let split = string.split("/")
    this.ipv4 = split[0]
    this.mask = Number.parseInt(split[1])
    return this
  }
  reset() {
    this.ipv4 = "127.0.0.0"
    this.mask = 0
  }
  toCompressedString(): string {
    return compressedIP(this.ipv4)+compressedMask(this.mask)
  }
  fromCompressedString(input: string): route {
    this.ipv4 = uncompressedIP(input.substring(0,4))
    this.mask = uncompressedMask(input.charAt(4))
    return this
  }
}
@ObservedV2
export class exit_node {
  @Trace ipv4: string = "10.0.0.2"
  toString(): string {
    return this.ipv4
  }
  from(network: exit_node): exit_node {
    this.ipv4 = network.ipv4
    return this
  }
  fromString(ip: string): exit_node {
    this.ipv4 = ip
    return this
  }
  reset() {
    this.ipv4 = "10.0.0.2"
  }
  toCompressedString(): string {
    return compressedIP(this.ipv4)
  }
  fromCompressedString(input: string): exit_node {
    this.ipv4 = uncompressedIP(input)
    return this
  }
}
@ObservedV2
export class vpn_portal_config {
  @Trace client_cidr: string = "10.0.1.0/24";
  @Trace wireguard_listen: string = "0.0.0.0:22020";
}
@ObservedV2
export class vpn_portal_config_with_config {
  @Trace client_cidr: string = "10.0.1.0/24";
  @Trace wireguard_listen: string = "0.0.0.0:22020";
  _config: Config | undefined
  constructor(config: Config | undefined = undefined) {
    if (config) {
      this._config = config
    }
  }
  @Monitor("client_cidr","wireguard_listen")
  onConfigChange(monitor: IMonitor) {
    if (this._config && !this._config._disableUpdate) {
      Manager.updateConfig(this._config)
      monitor.dirty.forEach((path: string) => {
        Logger.debug(`${path} changed from ${monitor.value(path)?.before} to ${monitor.value(path)?.now}`)
      })
    }
  }
  toCompressedString(): string {
    let split = this.client_cidr.split("/")
    let split2 = this.wireguard_listen.split(":")
    return compressedIP(split[0])+compressedMask(Number.parseInt(split[1]))+Number.parseInt(split2[1]).toString()
  }
  fromCompressedString(input: string) {
    this.client_cidr = uncompressedIP(input.substring(0,4))+"/"+compressedMask(input.charCodeAt(4))
    this.wireguard_listen = "0.0.0.0:"+input.substring(5)
  }
}
@ObservedV2
export class port_forward {
  @Trace bind_addr: string = "";
  @Trace dst_addr: string = "";
  @Trace proto: string = "";
}
@ObservedV2
export class network_whitelist {
  config: Config
  @Trace whitelist: SafeSet<WrappedString>;
  constructor(config: Config) {
    this.config = config
    this.whitelist = new SafeSet()
  }
  fromString(string: string): network_whitelist {
    if (string.length > 0) string.split(" ").forEach((value) => {
      this.whitelist.add(new WrappedString(value), !this.config._disableUpdate)
    })
    return this
  }
  toRawString(): string {
    let str = ""
    let index = 0
    this.whitelist.forEach((value:WrappedString) => {
      str += value.value
      if (index < this.whitelist.size - 1) {
        str += " "
      }
      index++
    })
    return str
  }
  toString(): string {
    let str = ""
    let index = 0
    this.whitelist.forEach((value:WrappedString) => {
      str += value.value
      if (index < this.whitelist.size - 1) {
        str += " "
      }
      index++
    })
    return '"'+str+'"'
  }
}
@ObservedV2
export class WrappedString {
  @Trace value: string = ""
  constructor(val: string = "") {
    this.value = val
  }
  from(val: WrappedString | string): WrappedString {
    if (val instanceof WrappedString) {
      this.value = val.value
      return this
    }else {
      this.value = val
      return this
    }
  }
  toString(): string {
    return this.value
  }
}
@ObservedV2
export class flags {
  @Trace accept_dns: boolean = false;
  @Trace disable_kcp_input: boolean = false;
  @Trace disable_p2p: boolean = false;
  @Trace disable_quic_input: boolean = false;
  @Trace disable_sym_hole_punching: boolean = false;
  @Trace disable_udp_hole_punching: boolean = false;
  @Trace enable_encryption: boolean = true;
  @Trace enable_exit_node: boolean = false;
  @Trace enable_ipv6: boolean = true;
  @Trace enable_kcp_proxy: boolean = false;
  @Trace enable_quic_proxy: boolean = false;
  @Trace latency_first: boolean = false;
  @Trace no_tun: boolean = false;
  @Trace private_mode: boolean = false;
  @Trace relay_all_peer_rpc: boolean = false;
  @Trace use_smoltcp: boolean = false;
  @Trace relay_network_whitelist: network_whitelist
  _config: Config
  constructor(config: Config) {
    this._config = config
    this.relay_network_whitelist = new network_whitelist(config)
  }
  @Monitor("accept_dns","disable_kcp_input","disable_p2p","disable_quic_input","disable_sym_hole_punching","disable_udp_hole_punching","enable_encryption","enable_exit_node","enable_ipv6",
  "enable_kcp_proxy","enable_quic_proxy","latency_first","no_tun","private_mode","relay_all_peer_rpc","use_smoltcp")
  onConfigChange(monitor: IMonitor) {
    if (this._config._disableUpdate) return
    Manager.updateConfig(this._config)
    monitor.dirty.forEach((path: string) => {
      Logger.debug(`${path} changed from ${monitor.value(path)?.before} to ${monitor.value(path)?.now}`)
    })
  }
  toCompressedString(): string {
    let result = ""
    Object.entries(this).forEach((pair:[string, valueType]) => {
      let key: string = safeFieldName(pair[0])
      let value: valueType = pair[1]
      if (value == null || key.startsWith("_")) {
      }else if (typeof value === "boolean") {
        result += (value as boolean)?"1":"0"
      }else if (value instanceof network_whitelist) {
        result += (value as network_whitelist).toRawString()
      }
    });
    return result
  }
  fromCompressedString(input: string) {
    for (let index = 0; index < 16; index++) {
      const element = input.charAt(index);
      switch (index) {
        case 0: this.accept_dns = uncompressedBoolean(element); break;
        case 1: this.disable_kcp_input = uncompressedBoolean(element); break;
        case 2: this.disable_p2p = uncompressedBoolean(element); break;
        case 3: this.disable_quic_input = uncompressedBoolean(element); break;
        case 4: this.disable_sym_hole_punching = uncompressedBoolean(element); break;
        case 5: this.disable_udp_hole_punching = uncompressedBoolean(element); break;
        case 6: this.enable_encryption = uncompressedBoolean(element); break;
        case 7: this.enable_exit_node = uncompressedBoolean(element); break;
        case 8: this.enable_ipv6 = uncompressedBoolean(element); break;
        case 9: this.enable_kcp_proxy = uncompressedBoolean(element); break;
        case 10: this.enable_quic_proxy = uncompressedBoolean(element); break;
        case 11: this.latency_first = uncompressedBoolean(element); break;
        case 12: this.no_tun = uncompressedBoolean(element); break;
        case 13: this.private_mode = uncompressedBoolean(element); break;
        case 14: this.relay_all_peer_rpc = uncompressedBoolean(element); break;
        case 15: this.use_smoltcp = uncompressedBoolean(element); break;
      }
    }
    this.relay_network_whitelist.fromString(input.substring(16))
  }
}
@ObservedV2
export class dhcp {
  @Trace enable: boolean = true
  @Trace ipv4: string = "10.0.0.1"
  @Trace mask: number = 24
  _config: Config | undefined
  constructor(config: Config | undefined = undefined) {
    if (config) {
      this._config = config
    }
  }
  @Monitor("enable","ipv4","mask")
  onConfigChange(monitor: IMonitor) {
    if (this._config && !this._config._disableUpdate) {
      Manager.updateConfig(this._config)
      monitor.dirty.forEach((path: string) => {
        Logger.debug(`${path} changed from ${monitor.value(path)?.before} to ${monitor.value(path)?.now}`)
      })
    }
  }
  toString(): string {
    if (this.enable) {
      return "true"
    }else {
      return 'false\nipv4 = "'+this.ipv4+'/'+this.mask+'"'
    }
  }
  toCompressedString(): string {
    if (this.enable) {
      return "1"
    }else {
      return compressedIP(this.ipv4)+compressedMask(this.mask)
    }
  }
  fromCompressedString(input: string) {
    if (input.length == 1) {
      this.enable = true
    }else {
      this.mask = uncompressedMask(input.charAt(input.length-1))
      this.ipv4 = uncompressedIP(input.substring(0, 4))
    }
  }
}
@ObservedV2
export class listener {
  @Trace _protocol: Protocol = Protocol.TCP
  @Trace _domain: string = "0.0.0.0"
  @Trace _port: number = 11010
  fromString(uri: string): listener {
    let split = uri.split("://")
    this._protocol = convertToProtocol(split[0])
    this._domain = split[1].split(":")[0]
    this._port = Number.parseInt(split[1].split(":")[1])
    return this
  }
  from(peer: listener): listener {
    this._protocol = peer._protocol
    this._domain = peer._domain
    this._port = peer._port
    return this
  }
  toString(): string {
    return this._protocol+"://"+this._domain+":"+this._port
  }
  toCompressedString(): string {
    return compressedProtocol(this._protocol)+this._domain+":"+this._port
  }
  fromCompressedString(input: string): listener {
    this._protocol = uncompressedProtocol(input.charAt(0))
    let split = input.substring(1).split(":")
    this._domain = split[0]
    this._port = Number.parseInt(split[1])
    return this
  }
  reset() {
    this._protocol = Protocol.TCP
    this._domain = "0.0.0.0"
    this._port = 11010
  }
}
@ObservedV2
export class socks5_proxy {
  @Trace port: string = "1080"
  _config: Config | undefined
  constructor(config: Config | undefined = undefined) {
    if (config) {
      this._config = config
    }
  }
  @Monitor("port")
  onConfigChange(monitor: IMonitor) {
    if (this._config && !this._config._disableUpdate) {
      Manager.updateConfig(this._config)
      monitor.dirty.forEach((path: string) => {
        Logger.debug(`${path} changed from ${monitor.value(path)?.before} to ${monitor.value(path)?.now}`)
      })
    }
  }
  fromString(string: string): socks5_proxy {
    this.port = string.substring(17)
    return this
  }
  toString(): string {
    return '"socks5://0.0.0.0:'+this.port+'"'
  }
  toCompressedString(): string {
    return this.port
  }
}
@ObservedV2
export class Config {
  _disableUpdate: boolean = false
  @Trace hostname: string = getHostname();
  @Trace instance_id: string = util.generateRandomUUID(true);
  @Trace instance_name: string = this.instance_id.substring(0, 8);
  @Trace dhcp: dhcp = new dhcp();
  @Trace listeners = new SafeSet<listener>();
  // @Trace mapped_listeners = new SafeLightWeightSet<listener>(this, () => {return new listener()});
  @Trace exit_nodes = new SafeSet<exit_node>();
  @Trace rpc_portal: string = "0.0.0.0:0";
  @Trace routes = new SafeSet<route>();
  @Trace socks5_proxy : socks5_proxy | null = null;
  @Trace network_identity: network_identity = new network_identity(this);
  @Trace peer = new SafeSet<peer>();
  @Trace proxy_network = new SafeSet<cidr>();
  @Trace vpn_portal_config: vpn_portal_config_with_config | null = null;
  // @Trace port_forward = new SafeSet<port_forward>(this);
  @Trace flags: flags = new flags(this);
  @Monitor("hostname","instance_name","socks5_proxy","vpn_portal_config")
  onConfigChange(monitor: IMonitor) {
    if (this._disableUpdate) return
    Manager.updateConfig(this)
    monitor.dirty.forEach((path: string) => {
      Logger.debug(`${path} changed from ${monitor.value(path)?.before} to ${monitor.value(path)?.now}`)
    })
  }
  initSocks5(input: string | undefined = undefined) {
    this.socks5_proxy = new socks5_proxy(this)
    if (input) {
      this.socks5_proxy.fromString(input)
    }
  }
  uncompressedSocks5(input: string) {
    this.socks5_proxy = new socks5_proxy(this)
    this.socks5_proxy.port = input
  }
  initPortal(input: vpn_portal_config | undefined = undefined) {
    this.vpn_portal_config = new vpn_portal_config_with_config(this)
    if (input) {
      this.vpn_portal_config.client_cidr = input.client_cidr
      this.vpn_portal_config.wireguard_listen = input.wireguard_listen
    }
  }
  uncompressedPortal(input: string) {
    this.vpn_portal_config = new vpn_portal_config_with_config(this)

  }
}