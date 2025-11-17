import { cidr, Config,
  dhcp,
  exit_node,
  flags,
  listener,
  network_identity,
  network_whitelist,
  peer,
  Protocol,
  route,
  socks5_proxy,
  vpn_portal_config_with_config} from "./ETConfig";
import { Logger } from "./Logger";
import { SafeSet } from "./SafeSet";
import { buffer } from "@kit.ArkTS";
import { BusinessError, zlib } from "@kit.BasicServicesKit";
import { objectToHomoTOML, safeFieldName } from "./Conversion";
import Manager from "../Manager";
import { SafeLightWeightSet } from "./SafeLightWeightSet";

const key_mapping: Record<string, string> = {
  "hostname": "a",
  "instance_id": "b",
  "instance_name": "c",
  "dhcp": "d",
  "listeners": "e",
  "mapped_listeners": "f",
  "exit_nodes": "g",
  "rpc_portal": "h",
  "routes": "i",
  "socks5_proxy": "j",
  "network_identity": "k",
  "peer": "l",
  "proxy_network": "m",
  "vpn_portal_config": "n",
  "flags": "o",
};

const BASE256_CHARS: string =
  '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz' +
    '!#$%&()*+,-./:;<=>?@[]^_`{|}~' +
    '¡¢£¤¥¦§¨©ª«¬®¯°±²³´µ¶·¸¹º»¼½¾¿' +
    'ÀÁÂÃÄÅÆÇÈÉÊËÌÍÎÏÐÑÒÓÔÕÖ×ØÙÚÛÜÝÞß' +
    'àáâãäåæçèéêëìíîïðñòóôõö÷øùúûüýþÿ' +
    'ĀāĂăĄąĆćĈĉĊċČčĎďĐđĒēĔĕĖėĘęĚěĜĝĞğ' +
    'ĠġĢģĤĥĦħĨĩĪīĬĭĮįİıĲĳĴĵĶķĸĹĺĻļĽľĿ';

export function uncompressedBoolean(input: string): boolean {
  return input=="1"
}

export function compressedFieldName(key: string): string {
  if (key.startsWith("__ob_")) {
    return key_mapping[key.substring(5)]
  }else if (key.startsWith("_")) {
    return key
  }else {
    return key_mapping[key]
  }
}

export function compressedProtocol(protocol: Protocol): string {
  switch (protocol) {
    case Protocol.TCP: return "0"
    case Protocol.UDP: return "1"
    case Protocol.QUIC: return "2"
    case Protocol.WS: return "3"
    case Protocol.WSS: return "4"
    case Protocol.WG: return "5"
    default: return "6"
  }
}

export function uncompressedProtocol(input: string): Protocol {
  let protocols = [Protocol.TCP, Protocol.UDP, Protocol.QUIC, Protocol.WS, Protocol.WSS, Protocol.WG, Protocol.UNKNOWN]
  return protocols[Number.parseInt(input)]
}

export function compressedIP(addr:string):string {
  let result = ""
  addr.split(".").forEach((value) => {
    result += BASE256_CHARS.charAt(Number.parseInt(value))
  })
  return result
}

export function uncompressedIP(input:string):string {
  let result = ""
  for (let index = 0; index < input.length; index++) {
    const element = input.charAt(index);
    result += BASE256_CHARS.indexOf(element)
    if (index < input.length - 1) {
      result+="."
    }
  }
  return result
}

type setType = SafeLightWeightSet<cidr> | SafeLightWeightSet<peer> | SafeLightWeightSet<string> | SafeLightWeightSet<route> | SafeLightWeightSet<exit_node> | SafeLightWeightSet<listener>
type elementType = cidr | peer | string | route | exit_node | listener
export type valueType = dhcp | socks5_proxy | flags | vpn_portal_config_with_config | cidr | peer | network_identity | string | number | boolean | listener | route | exit_node | SafeLightWeightSet<cidr> | SafeLightWeightSet<peer> | SafeLightWeightSet<string> | null
type compressedValueType = string | number

export function compressedMask(mask:number):string {
  return BASE256_CHARS.charAt(mask)
}

export function uncompressedMask(input:string):number {
  return BASE256_CHARS.indexOf(input)
}

export function compressedValue(value: valueType): compressedValueType {
  if (typeof value === "boolean") {
    return value?1:0
  }else if (typeof value === "string") {
    return value as string
  }else if (typeof value === "number") {
    return value as number
  }else if (value instanceof flags) {
    return value.toCompressedString()
  // }else if (value instanceof port_forward) {
  //   return ""
  }else if (value instanceof dhcp) {
    return value.toCompressedString()
  }else if (value instanceof socks5_proxy) {
    return value.toCompressedString()
  }else if (value instanceof vpn_portal_config_with_config) {
    return value.toCompressedString()
  }else if (value instanceof cidr) {
    return value.toCompressedString()
  }else if (value instanceof peer) {
    return value.toCompressedString()
  }else if (value instanceof network_identity) {
    return value.toString()
  }else if (value instanceof listener) {
    return value.toCompressedString()
  }else if (value instanceof route) {
    return value.toCompressedString()
  }else if (value instanceof exit_node) {
    return value.toCompressedString()
  // }else if (value instanceof SafeSet<port_forward>) {
  //   return ""
  }else {
    let arr = value as setType
    let result = ""
    let index = 0
    arr.forEach((value: elementType) => {
      result += compressedValue(value)
      if (index < arr.size - 1) {
        result+=","
      }
      index++
    })
    return result
  }
}

export function uncompressedListeners(input: string, set: SafeSet<listener>) {
  let split = input.split(",")
  split.forEach((value) => {
    set.add(new listener().fromCompressedString(value))
  })
}

export function uncompressedExitNodes(input: string, set: SafeSet<exit_node>) {
  let split = input.split(",")
  split.forEach((value) => {
    set.add(new exit_node().fromCompressedString(value))
  })
}

export function uncompressedRoutes(input: string, set: SafeSet<route>) {
  let split = input.split(",")
  split.forEach((value) => {
    set.add(new route().fromCompressedString(value))
  })
}

export function uncompressedPeers(input: string, set: SafeSet<peer>) {
  let split = input.split(",")
  split.forEach((value) => {
    set.add(new peer().fromCompressedString(value))
  })
}

export function uncompressedCidrs(input: string, set: SafeSet<cidr>) {
  let split = input.split(",")
  split.forEach((value) => {
    set.add(new cidr().fromCompressedString(value))
  })
}

export async function compressedConfig(config: Config): Promise<string> {
  Logger.debug("before compressed:\n"+objectToHomoTOML(config))
  let str = "";
  Object.entries(config).forEach((pair:[string, valueType]) => {
    let key: string = compressedFieldName(pair[0])
    let value: valueType = pair[1]

    if (value == null || key.startsWith("_") || key == "f" || key == "h") {
    }else {
      str+=key+compressedValue(value)+"\n"
    }
  });
  Logger.info("mapping:\n"+str)
  let buf = buffer.from(str).buffer
  let arrayBufferOut = new ArrayBuffer(buf.byteLength);
  let zip = zlib.createZipSync();
  await zip.compress2(arrayBufferOut, buf, zlib.CompressLevel.COMPRESS_LEVEL_BEST_COMPRESSION)
  let result = buffer.from(arrayBufferOut).toString("base64url")
  Logger.debug("compressed:\n"+result)
  return result
}

export async function uncompressedConfig(input: string): Promise<Config> {
  let buf2 = buffer.from(input,"base64url").buffer
  let arrayBufferOut2 = new ArrayBuffer(500);
  let zip = zlib.createZipSync();
  zip.uncompress2(arrayBufferOut2, buf2).then(() => {
    let unzip = buffer.from(arrayBufferOut2).toString()
    Logger.info("after uncompressed:\n"+unzip)
    let config = new Config()
    config._disableUpdate = true
    unzip.split("\n").forEach((line) => {
      let key = line.charAt(0)
      let value = line.substring(1, line.length)
      switch (key) {
        case "a": config.hostname = value; break;
        case "b": config.instance_id = value; break;
        case "c": config.instance_name = value; break;
        case "d": config.dhcp.fromCompressedString(value); break;
        case "e": uncompressedListeners(value, config.listeners); break;
        case "g": uncompressedExitNodes(value, config.exit_nodes); break;
        case "h": break;
        case "i": uncompressedRoutes(value, config.routes); break;
        case "j": config.uncompressedSocks5(value); break;
        case "k": config.network_identity.fromString(value); break;
        case "l": uncompressedPeers(value, config.peer); break;
        case "m": uncompressedCidrs(value, config.proxy_network); break;
        case "n": config.uncompressedPortal(value); break;
        case "o": config.flags.fromCompressedString(value); break;
      }
    })
    config._disableUpdate = false
    Logger.debug("after unmapping:\n"+objectToHomoTOML(config))
    return config
  }).catch((errData: BusinessError) => {
    return Promise.reject<Config>(`errData is errCode:${errData.code}  message:${errData.message}`)
  });
  return Promise.reject<Config>(`empty`)
}

export async function readConfig(input: string) {
  uncompressedConfig(input).then((value) => {
    Manager.addConfig(value)
  },(reason: string) => {
    Logger.error(reason)
  })
}