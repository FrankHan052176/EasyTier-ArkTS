import { isGetDistributePerm } from "./Permission"
import Manager from "../Manager"
import { Config,
  dhcp,
  flags,
  listener,
  network_identity,
  network_whitelist,
  peer, port_forward, cidr,
  socks5_proxy,
  vpn_portal_config,
  route,
  exit_node} from "./config/ETConfig"
import { SafeSet } from "./SafeSet"
import { NetworkInstanceRunningInfo, NetworkInstanceRunningInfoWithUnwrappedEvents } from "./info/PeerInfo"
import { Event } from "../util/info/PeerInfo"
import Logger from "./Logger"
import EventHelper from "./EventHelper"
import { toml2json } from "libentry.so"
import { SafeLightWeightSet } from "./SafeLightWeightSet"

export function tomlToConfig(toml: string): Config | undefined {
  try {
    let json = toml2json(toml)
    return flattenConfig(JSON.parse(json) as object)
  }catch (e) {
    return undefined
  }
}

export function trafficBytes(bytes: number): string {
  if (bytes > 107374182) {
    return (bytes/1073741824).toFixed(1)+"GB/s"
  }else if (bytes > 104858) {
    return (bytes/1048576).toFixed(1)+"MB/s"
  }else if (bytes > 102) {
    return (bytes/1024).toFixed(1)+"KB/s"
  }else {
    return bytes+"B/s"
  }
}

export function runningTime(time: number): string {
  if (time > 360) {
    return (time/3600).toFixed(1)+"h"
  }else if (time > 60) {
    return (time/60).toFixed(1)+"min"
  }else {
    return time+"sec"
  }
}

export function convertAddrToIp(addr: number): string {
  const byte1 = (addr >> 24) & 0xFF;
  const byte2 = (addr >> 16) & 0xFF;
  const byte3 = (addr >> 8) & 0xFF;
  const byte4 = addr & 0xFF;

  return `${byte1}.${byte2}.${byte3}.${byte4}`;
}

export function convertDeviceTypeToSymbol(type: string): Resource {
  switch (type) {
    case "PHONE": {
      return $r("sys.symbol.phone")
    }
    case "PAD": {
      return $r("sys.symbol.pad")
    }
    case "PC": {
      return $r("sys.symbol.pc")
    }
    default: {
      return $r("sys.symbol.unknown_device")
    }
  }
}

export function convertDeviceNumberToSymbol(type: number): Resource {
  switch (type) {
    case 14: {
      return $r("sys.symbol.phone_fill_1")
    }
    case 17: {
      return $r("sys.symbol.pad_fill")
    }
    case 2607: {
      return $r("sys.symbol.computer_fill")
    }
    default: {
      return $r("sys.symbol.unknown_device_fill")
    }
  }
}

export function betterHeight(size: number, lanes: number, item_height: number): number {
  let scale = Math.min(Math.floor((size+1)/lanes), 3)
  let mod = (size+1) % lanes
  return scale >= 1?item_height*(scale+(mod>0?0.7:0))+10*(scale-1):item_height
}

export function getHostname(): string {
  return isGetDistributePerm()?Manager.deviceManager.getLocalDeviceName():"HarmonyOS"
}

export function hashString(str: string): number {
  let hash = 0;
  for (let i = 0; i < str.length; i++) {
    hash = str.charCodeAt(i) + ((hash << 5) - hash);
  }
  return hash;
}
export function hashToColor(hash: number): string {
  // 使用哈希值生成RGB分量
  const r = (hash & 0xFF0000) >> 16;
  const g = (hash & 0x00FF00) >> 8;
  const b = hash & 0x0000FF;

  // 转换为十六进制
  return `#${((1 << 24) + (r << 16) + (g << 8) + b).toString(16).slice(1)}`;
}

export function safePassword(pwd: string): string {
  if (pwd.length > 4) {
    return pwd.substring(0,2)+"·".repeat(pwd.length-2)
  }else {
    if (pwd.length == 0) {
      return " "
    }else {
      return "·".repeat(pwd.length)
    }
  }
}

type tomlType = Config | flags | port_forward | vpn_portal_config | cidr | peer | network_identity | listener | exit_node | string | number | boolean | null
type arrayType = SafeSet<port_forward> | SafeSet<cidr> | SafeSet<peer> | SafeSet<string> | SafeSet<listener> | SafeSet<exit_node>
type elementType = port_forward | cidr | peer | string | listener | exit_node

export function safeFieldName(key: string): string {
  if (key.startsWith("__ob_")) {
    return key.substring(5)
  }else {
    return key
  }
}

export function objectToHomoTOML(obj: tomlType): string {
  let tomlString = "";
  if (obj === null) return tomlString
  Object.entries(obj).forEach((pair:[string, tomlType]) => {
    let key: string = safeFieldName(pair[0])
    let value: tomlType = pair[1]
    if (value === null || key.startsWith("_")){
    } else if (value instanceof SafeSet) {
      let set = value as arrayType
      if (set.size > 0) {
        if (
          set.map.values().next().value instanceof String ||
            set.map.values().next().value instanceof listener ||
            set.map.values().next().value instanceof route ||
            set.map.values().next().value instanceof exit_node
        ) {
          tomlString += `${key} = [\n`;
          set.forEach((item: elementType) => {
            tomlString += `    "${item}",\n`;
          })
          tomlString += `]\n`;
        }else {
          set.forEach((item: elementType) => {
            tomlString += `[[${key}]]\n`;
            if (item instanceof cidr || item instanceof peer) {
              tomlString += `${item}\n`;
            }else {
              tomlString += objectToHomoTOML(item)+"\n"
            }
          })
        }
      }
    } else if (typeof value === "string") {
      tomlString += `${key} = "${value}"\n`;
    } else if (
      value instanceof dhcp ||
        value instanceof socks5_proxy ||
        value instanceof network_whitelist
    ) {
      tomlString += `${key} = ${value}\n`;
    } else if (typeof value === "object") {
      tomlString += `\n[${key}]\n`;
      tomlString += objectToHomoTOML(value);
    } else {
      tomlString += `${key} = ${value}\n`;
    }
  });
  return tomlString + `\n`;
}

export function formatDate(date: Date): string {
  const hours = date.getHours().toString().padStart(2, '0');
  const minutes = date.getMinutes().toString().padStart(2, '0');
  const seconds = date.getSeconds().toString().padStart(2, '0');
  const fullMilliseconds = date.getMilliseconds().toString().padStart(3, '0');
  const hundredAndTenMilliseconds = fullMilliseconds.slice(0, 2);

  return `${hours}:${minutes}:${seconds}.${hundredAndTenMilliseconds}`;
}

interface WrappedEvent {
  time: string
  event: object
}

export function unwrappedEvents(info: NetworkInstanceRunningInfo, uuid: string): NetworkInstanceRunningInfoWithUnwrappedEvents {
  let events = info.events
  let newEvents = new Array<Event>()
  let config = Manager.configs.get(uuid)
  if (config) {
    events.forEach((value) => {
      let obj: WrappedEvent = JSON.parse(value)
      let time = formatDate(new Date(obj.time))
      Object.entries(obj.event).forEach((value: [string, string | object], index) => {
        let msg = ""
        if (value[1] instanceof String) {
          msg = value[1] as string
        }else {
          msg = JSON.stringify(value[1])
        }
        newEvents.push({
          time: time,
          type: value[0],
          msg: msg
        })
        if (Manager.needTunInstances.has(uuid) && info.my_node_info.virtual_ipv4 !== null) {
          Manager.needTunInstances.delete(uuid)
          EventHelper.emitterPublish("setup_tun", {
            data: {
              ip: convertAddrToIp(info.my_node_info.virtual_ipv4.address.addr),
              mask: info.my_node_info.virtual_ipv4.network_length,
              id: uuid,
              magicDNS: config!.flags.accept_dns
            }
          })
        }
      })
    })
  }else {
    Logger.error("[Conversion::unwrappedEvents] Cant find config["+uuid+"]")
  }
  return {
    dev_name: info.dev_name,
    my_node_info: info.my_node_info,
    events: newEvents,
    routes: info.routes,
    peers: info.peers,
    peer_route_pairs: info.peer_route_pairs,
    running: info.running,
    error_msg: info.error_msg
  }
}

export function flattenConfig(obj: object): Config {
  let config = new Config()
  config._disableUpdate = true
  if (obj["hostname"]) {
    config.hostname = obj["hostname"]
  }else {
    config.hostname = getHostname()
  }
  config.instance_id = obj["instance_id"]
  config.instance_name = obj["instance_name"] as string
  // dhcp
  config.dhcp.enable = obj["dhcp"] as boolean
  if (!config.dhcp.enable) {
    let ipv4 = (obj["ipv4"] as string).split("/")
    config.dhcp.ipv4 = ipv4[0]
    config.dhcp.mask = Number.parseInt(ipv4[1])
  }
  // listener
  if (obj["listeners"]) {
    let listeners = obj["listeners"] as Array<string>
    listeners.forEach((value) => {
      config.listeners.add(new listener().fromString(value), false)
    })
  }
  // // mapped_listener
  // if (obj["mapped_listeners"]) {
  //   let mapped_listeners = obj["mapped_listeners"] as Array<string>
  //   mapped_listeners.forEach((value) => {
  //     config.mapped_listeners.add(new listener().fromString(value), false)
  //   })
  // }
  // exit_node
  if (obj["exit_nodes"]) {
    let exit_nodes = obj["exit_nodes"] as Array<string>
    exit_nodes.forEach((value) => {
      config.exit_nodes.add(new exit_node().fromString(value), false)
    })
  }
  // route
  if (obj["routes"]) {
    let routes = obj["routes"] as Array<string>
    routes.forEach((value) => {
      config.routes.add(new route().fromString(value), false)
    })
  }
  // socks5_proxy
  let socks5: string | undefined = obj["socks5_proxy"]
  if (socks5) {
    config.initSocks5(socks5)
  }
  // network_identity
  config.network_identity.from(obj["network_identity"] as network_identity)
  // peers
  if (obj["peer"]) {
    let peers = obj["peer"] as Array<object>
    peers.forEach((value) => {
      config.peer.add(new peer().setUri(value["uri"] as string), false)
    })
  }
  // proxy_networks
  if (obj["proxy_network"]) {
    let proxy_networks = obj["proxy_network"] as Array<object>
    proxy_networks.forEach((value) => {
      config.proxy_network.add(new cidr().fromString(value["cidr"] as string), false)
    })
  }
  // vpn_portal
  let vpn_portal: vpn_portal_config | undefined = obj["vpn_portal_config"]
  if (vpn_portal) {
    config.initPortal(vpn_portal)
  }
  // // port_forward
  // if (obj["port_forward"]) {
  //   let port_forwards = obj["port_forward"] as Array<port_forward>
  //   port_forwards.forEach((value) => {
  //     config.port_forward.add(value, false)
  //   })
  // }
  // flags
  let flagsObj: object = obj["flags"]
  if (flagsObj) {
    let whitelist = flagsObj["relay_network_whitelist"]?String(flagsObj["relay_network_whitelist"]):""
    config.flags.accept_dns = Boolean(flagsObj["accept_dns"]);
    config.flags.disable_kcp_input = Boolean(flagsObj["disable_kcp_input"]);
    config.flags.disable_p2p = Boolean(flagsObj["disable_p2p"]);
    config.flags.disable_quic_input = Boolean(flagsObj["disable_quic_input"]);
    config.flags.disable_sym_hole_punching = Boolean(flagsObj["disable_sym_hole_punching"]);
    config.flags.disable_udp_hole_punching = Boolean(flagsObj["disable_udp_hole_punching"]);
    config.flags.enable_encryption = flagsObj["enable_encryption"]?flagsObj["enable_encryption"]:true;
    config.flags.enable_exit_node = Boolean(flagsObj["enable_exit_node"]);
    config.flags.enable_ipv6 = flagsObj["enable_ipv6"]?flagsObj["enable_encryption"]:true;
    config.flags.enable_kcp_proxy = Boolean(flagsObj["enable_kcp_proxy"]);
    config.flags.enable_quic_proxy = Boolean(flagsObj["enable_quic_proxy"]);
    config.flags.latency_first = Boolean(flagsObj["latency_first"]);
    config.flags.no_tun = Boolean(flagsObj["no_tun"]);
    config.flags.private_mode = Boolean(flagsObj["private_mode"]);
    config.flags.relay_all_peer_rpc = Boolean(flagsObj["relay_all_peer_rpc"]);
    config.flags.relay_network_whitelist.fromString(whitelist)
    config.flags.use_smoltcp = Boolean(flagsObj["use_smoltcp"]);
  }
  config._disableUpdate = false
  return config
}