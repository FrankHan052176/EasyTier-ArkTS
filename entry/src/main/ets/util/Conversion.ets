import { UIType, WindowUtil } from '../WindowUtil'
import { AppManager } from '../AppManager'
import { connection } from '@kit.NetworkKit'
import { NetworkSegment } from '../class/NetworkSegment'

export function trafficBytes(bytes: number): string {
  if (bytes > 107374182) {
    return (bytes / 1073741824).toFixed(1) + "GB/s"
  } else if (bytes > 104858) {
    return (bytes / 1048576).toFixed(1) + "MB/s"
  } else if (bytes > 102) {
    return (bytes / 1024).toFixed(1) + "KB/s"
  } else {
    return bytes + "B/s"
  }
}

export function runningTime(time: number): string {
  if (time > 360) {
    return (time / 3600).toFixed(1) + "h"
  } else if (time > 60) {
    return (time / 60).toFixed(1) + "min"
  } else {
    return time + "sec"
  }
}

export function lane(need: number): number {
  switch (WindowUtil.uiType) {
    case UIType.Column_1: {
      let scale = Math.min(2, Math.max(1, need))
      if (scale == 2) {
        return WindowUtil.width - 30
      } else {
        return preciseIntegerDivision(WindowUtil.width - 40, 2)
      }
    }
    case UIType.Column_2: {
      let scale = Math.min(4, Math.max(1, need))
      if (scale == 4) {
        return WindowUtil.width - 30
      } else {
        return preciseIntegerDivision((WindowUtil.width - 60) * scale, 4) + (scale - 1) * 10
      }
    }
    case UIType.Column_3: {
      let scale = Math.min(6, Math.max(1, need))
      if (scale == 6) {
        return WindowUtil.width - 30
      } else {
        return preciseIntegerDivision((WindowUtil.width - 80) * scale, 6) + (scale - 1) * 10
      }
    }
    default: {
      return 0
    }
  }
}

export function preciseIntegerDivision(a: number, b: number) {
  const result = a / b;
  if (Math.abs(result - Math.round(result)) < 1e-10) {
    return Math.round(result);
  }
  return result;
}

export function convertAddrToIp(addr: number | number[]): string {
  if (Array.isArray(addr)) {
    return addr.join('.')
  }
  const byte1 = (addr >> 24) & 0xFF;
  const byte2 = (addr >> 16) & 0xFF;
  const byte3 = (addr >> 8) & 0xFF;
  const byte4 = addr & 0xFF;

  return `${byte1}.${byte2}.${byte3}.${byte4}`;
}

export function getHostname(): string {
  return AppManager.permission.isGetDistributePerm() ? AppManager.content.deviceManager.getLocalDeviceName() :
    "HarmonyOS"
}

export function safePassword(pwd: string): string {
  if (pwd.length > 4) {
    return pwd.substring(0, 2) + "·".repeat(pwd.length - 2)
  } else {
    if (pwd.length == 0) {
      return " "
    } else {
      return "·".repeat(pwd.length)
    }
  }
}

export function logColor(log: string): ResourceColor {
  let level = Number.parseInt(log.charAt(0))
  if (level >= 6) {
    return $r("sys.color.warning")
  } else if (level == 5) {
    return $r("sys.color.alert")
  } else {
    return $r("sys.color.font_primary")
  }
}

export function stringArr2RouteArr(gateway: string, magicDNS: boolean, needExitNode: boolean, customRoutes?: NetworkSegment[], forceGlobal?: boolean): connection.RouteInfo[] {
  let result: connection.RouteInfo[] = []
  let routes = customRoutes || Array.from(AppManager.easytier.tunRoutes)
  let isForceGlobal = forceGlobal !== undefined ? forceGlobal : AppManager.uiState.force_global
  const seenRoutes: Set<string> = new Set()

  routes.forEach((route) => {
    const routeKey = `${route.networkAddress}/${route.prefix}`
    if (seenRoutes.has(routeKey)) {
      return
    }
    seenRoutes.add(routeKey)
    result.push({
      interface: "vpn-tun",
      destination: {
        address: {
          address: route.networkAddress
        },
        prefixLength: route.prefix
      },
      gateway: {
        address: gateway
      },
      hasGateway: true,
      isDefaultRoute: false,
    })
  })
  if (magicDNS) {
    result.push({
      interface: "vpn-tun",
      destination: {
        address: {
          address: "100.100.100.101"
        },
        prefixLength: 32
      },
      gateway: {
        address: gateway
      },
      hasGateway: true,
      isDefaultRoute: false,
    })
  }
  if (needExitNode && isForceGlobal) {
    result.push({
      interface: "vpn-tun",
      destination: {
        address: {
          address: "0.0.0.0"
        },
        prefixLength: 0
      },
      gateway: {
        address: gateway
      },
      hasGateway: true,
      isDefaultRoute: false,
    })
  }
  return result
}

export function mergeRouteStrings(primary?: string[], secondary?: string[]): string[] {
  const merged: string[] = []
  const seen: Set<string> = new Set()
  ;[...(primary ?? []), ...(secondary ?? [])].forEach((route) => {
    if (route.length === 0 || seen.has(route)) {
      return
    }
    seen.add(route)
    merged.push(route)
  })
  return merged
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
  TXT = "txt",
  UNKNOWN = "N/A"
}

export const protocols =
  [Protocol.TCP, Protocol.UDP, Protocol.QUIC, Protocol.WS, Protocol.WSS, Protocol.WG, Protocol.TXT]

export const protocolsWithoutTXT = [Protocol.TCP, Protocol.UDP, Protocol.QUIC, Protocol.WS, Protocol.WSS, Protocol.WG]

export const protocolsOnlyTcpAndUdp = [Protocol.TCP, Protocol.UDP]

export function convertToProtocol(input: string): Protocol {
  switch (input) {
    case "tcp":
      return Protocol.TCP;
    case "tcp6":
      return Protocol.TCP6;
    case "udp":
      return Protocol.UDP;
    case "udp6":
      return Protocol.UDP6;
    case "quic":
      return Protocol.QUIC;
    case "quic6":
      return Protocol.QUIC6;
    case "ws":
      return Protocol.WS;
    case "ws6":
      return Protocol.WS6;
    case "wss":
      return Protocol.WSS;
    case "wss6":
      return Protocol.WSS6;
    case "wg":
      return Protocol.WG;
    case "wg6":
      return Protocol.WG6;
    case "txt":
      return Protocol.TXT;
    default:
      return Protocol.UNKNOWN;
  }
}

export function protocolColor(protocol: Protocol): ResourceColor {
  switch (protocol) {
    case Protocol.UDP:
      return "#ffd94838";
    case Protocol.QUIC:
      return "#ff800080";
    case Protocol.WS:
      return "#ff64bb5c";
    case Protocol.WSS:
      return "#ff5ba854";
    case Protocol.WG:
      return "#ffed6f21";
    case Protocol.TXT:
      return $r("sys.color.font_on_primary");
    default:
      return "#ff0a59f7";
  }
}

export function protocolBGColor(protocol: Protocol): ResourceColor {
  switch (protocol) {
    case Protocol.UDP:
      return "#33d94838";
    case Protocol.QUIC:
      return "#33800080";
    case Protocol.WS:
      return "#3364bb5c";
    case Protocol.WSS:
      return "#335ba854";
    case Protocol.WG:
      return "#33ed6f21";
    case Protocol.TXT:
      return $r("sys.color.font_primary");
    default:
      return "#330a59f7";
  }
}
