import { PermissionUtil } from "../PermissionUtil"
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
  exit_node,
  WrappedString,
  SharedPeer} from "./ETConfig"
import { SafeSet } from "./SafeSet"
import {
  Event,
  NetworkInstanceRunningInfo, NetworkInstanceRunningInfoWithUnwrappedEvents,
  PeerRoutePair } from "./info/PeerInfo"
import { Logger } from "./Logger"
import { toml2json } from "libentry.so"
import { SafeLightWeightSet } from "./SafeLightWeightSet";
import { display } from "@kit.ArkUI"
import { UIType, WindowUtil } from "../WindowUtil"
import { AppManager } from "../AppManager"

export function tomlToConfig(toml: string): Config | undefined {
  try {
    let json = toml2json(toml)
    if (json == "ERROR") {
      return undefined
    }else {
      return flattenConfig(JSON.parse(json) as object)
    }
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

export function lane(need: number): number {
  switch (WindowUtil.uiType) {
    case UIType.Column_1: {
      let scale = Math.min(2,Math.max(1, need))
      if (scale == 2) {
        return WindowUtil.width-30
      }else {
        return (WindowUtil.width-40)/2
      }
    }
    case UIType.Column_2: {
      let scale = Math.min(4,Math.max(1, need))
      if (scale == 4) {
        return WindowUtil.width-30
      }else {
        return (WindowUtil.width-60)/4*scale+(scale-1)*10
      }
    }
    case UIType.Column_3: {
      let scale = Math.min(6,Math.max(1, need))
      if (scale == 6) {
        return WindowUtil.width-30
      }else {
        return (WindowUtil.width-80)/6*scale+(scale-1)*10
      }
    }
    default: {
      return 0
    }
  }
}

export function preciseIntegerDivision(a:number, b:number) {
  const result = a / b;
  if (Math.abs(result - Math.round(result)) < 1e-10) {
    return Math.round(result);
  }
  return result;
}

export function convertAddrToIp(addr: number): string {
  const byte1 = (addr >> 24) & 0xFF;
  const byte2 = (addr >> 16) & 0xFF;
  const byte3 = (addr >> 8) & 0xFF;
  const byte4 = addr & 0xFF;

  return `${byte1}.${byte2}.${byte3}.${byte4}`;
}

export function getHostname(): string {
  return AppManager.permission.isGetDistributePerm()?Manager.deviceManager.getLocalDeviceName():"HarmonyOS"
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

export type lwElementType = port_forward | cidr | peer | listener | exit_node | route | WrappedString | network_identity

export function elementCode(element: object): string {
  if (element instanceof cidr) {
    return "cidr"
  }else if (element instanceof peer) {
    return "peer"
  }else if (element instanceof listener) {
    return "listener"
  }else if (element instanceof exit_node) {
    return "exit_node"
  }else if (element instanceof WrappedString) {
    return "wl"
  }else if (element instanceof network_identity) {
    return "network_identity"
  }else if (element instanceof route) {
    return "route"
  }else {
    return ""
  }
}

export function elementString(element: lwElementType): string {
  if (element instanceof cidr) {
    return element.toRawString()
  }else {
    return element.toString()
  }
}

export function updateElement(element: lwElementType, add: boolean = true) {
  // if (add) {
  //   Manager.KVStore?.put(elementCode(element)+"_"+elementString(element), elementString(element)).catch(() => {
  //     Logger.error(`[Manager] cidrs::put::An unexpected error occurred.`);
  //   })
  // }else {
  //   Manager.KVStore?.delete(elementCode(element)+"_"+elementString(element)).catch(() => {
  //     Logger.error(`[Manager] exit_nodes::delete::An unexpected error occurred.`);
  //   })
  // }
}

export function logColor(log: string): ResourceColor {
  let level = Number.parseInt(log.charAt(0))
  if (level >= 6) {
    return $r("sys.color.warning")
  }else if (level == 5) {
    return $r("sys.color.alert")
  }else {
    return $r("sys.color.font_primary")
  }
}

type tomlType = Config | flags | port_forward | vpn_portal_config | cidr | peer | network_identity | listener | exit_node | string | number | boolean | null
type setType = SafeSet<port_forward> | SafeSet<cidr> | SafeSet<peer> | SafeSet<listener> | SafeSet<exit_node> | SafeSet<route>
type elementType = port_forward | cidr | peer | listener | exit_node | route

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
      let set = value as setType
      if (set.size > 0) {
        if (
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

function handleEventMsg(type: string, value: string | object): string {
  switch (type) {
    case "DhcpIpv4Changed": return `${value[0]} -> ${value[1]}`
    default: return JSON.stringify(value, null, 2)
  }
}

export function unwrappedRawEvent(raw: string): Event {
  let obj: WrappedEvent = JSON.parse(raw)
  let time = formatDate(new Date(obj.time))
  Object.entries(obj.event).forEach((value: [string, string | object]) => {
    let msg = ""
    if (typeof value[1] == "string") {
      msg = value[1]
    }else {
      msg = handleEventMsg(value[0], value[1])
    }
    return {
      time: time,
      type: value[0],
      msg: msg
    } as Event
  })
  return {
    time: "",
    type: "",
    msg: ""
  }
}

export function handleNewInfo(info: NetworkInstanceRunningInfo, uuid: string) {
  // if (Manager.info == undefined) {
  //   Manager.info = new NetworkInstanceRunningInfoWithUnwrappedEvents()
  // }
  // let newInfo = Manager.info!
  // let config = Manager.configs.get(uuid)
  // if (config) {
  //   newInfo.events.splice(0, newInfo.events.length)
  //   info.events.forEach((value) => {
  //
  //   })
  //   newInfo.events = newInfo.events.slice()
  //   newInfo.dev_name = info.dev_name
  //   newInfo.my_node_info = info.my_node_info
  //   newInfo.routes.splice(0, newInfo.routes.length)
  //   info.routes.forEach((value) => {
  //     newInfo.routes.push(value)
  //   })
  //   newInfo.routes = newInfo.routes.slice()
  //   newInfo.peers.splice(0, newInfo.peers.length)
  //   info.peers.forEach((value) => {
  //     newInfo.peers.push(value)
  //   })
  //   newInfo.peers = newInfo.peers.slice()
  //   newInfo.peer_route_pairs.splice(0, newInfo.peer_route_pairs.length)
  //   info.peer_route_pairs.forEach((value) => {
  //     newInfo.peer_route_pairs.push(value)
  //   })
  //   newInfo.peer_route_pairs = newInfo.peer_route_pairs.slice()
  //   newInfo.running = info.running
  //   newInfo.error_msg = info.error_msg
  // }else {
  //   Logger.error("[Conversion::unwrappedEvents] Cant find config["+uuid+"]")
  // }
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