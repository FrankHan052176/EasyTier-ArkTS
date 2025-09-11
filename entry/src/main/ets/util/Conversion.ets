import { isGetDistributePerm } from "./Permission"
import { distributedDeviceManager } from "@kit.DistributedServiceKit"
import {  } from "./Conversion"
import Manager from "../Manager"

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
    case -14: {
      return $r("sys.symbol.phone")
    }
    case -17: {
      return $r("sys.symbol.pad")
    }
    case -2607: {
      return $r("sys.symbol.pc")
    }
    default: {
      return $r("sys.symbol.unknown_device")
    }
  }
}

export function getHostname(): string {
  return isGetDistributePerm()?Manager.deviceManager.getLocalDeviceName():"HarmonyOS"
}

export function objectToTOML(obj: object, indent: string = ""): string {
  let tomlString = "";
  Object.entries(obj).forEach(([key, value]) => {
    const currentIndent = indent + "  ";
    if (Array.isArray(value)) {
      tomlString += `${indent}${key} = [\n`;
      for (const item of value) {
        if (typeof item === "string") {
          tomlString += `${currentIndent}"${item}",\n`;
        } else if (typeof item === "boolean" || typeof item === "number") {
          tomlString += `${currentIndent}${item},\n`;
        }
      }
      tomlString += `${indent}]\n`;
    } else if (typeof value === "object" && value !== null) {
      tomlString += `${indent}[${key}]\n`;
      tomlString += objectToTOML(value, currentIndent);
    } else if (typeof value === "string" && value !== null) {
      tomlString += `${indent}${key} = "${value}"\n`;
    } else if (value !== null) {
      tomlString += `${indent}${key} = ${value}\n`;
    }
  });
  return tomlString;
}