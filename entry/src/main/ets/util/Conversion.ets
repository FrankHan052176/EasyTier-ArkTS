import { UIType, WindowUtil } from "../WindowUtil"
import { AppManager } from "../AppManager"
import { connection } from "@kit.NetworkKit"

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
        return preciseIntegerDivision(WindowUtil.width-40,2)
      }
    }
    case UIType.Column_2: {
      let scale = Math.min(4,Math.max(1, need))
      if (scale == 4) {
        return WindowUtil.width-30
      }else {
        return preciseIntegerDivision((WindowUtil.width-60)*scale,4)+(scale-1)*10
      }
    }
    case UIType.Column_3: {
      let scale = Math.min(6,Math.max(1, need))
      if (scale == 6) {
        return WindowUtil.width-30
      }else {
        return preciseIntegerDivision((WindowUtil.width-80)*scale,6)+(scale-1)*10
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
  return AppManager.permission.isGetDistributePerm()?AppManager.content.deviceManager.getLocalDeviceName():"HarmonyOS"
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

export function stringArr2RouteArr(gateway: string, magicDNS: boolean, needExitNode: boolean): connection.RouteInfo[] {
  let result:connection.RouteInfo[] = []
  AppManager.easytier.tunRoutes.forEach((route) => {
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
  if (needExitNode) {
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