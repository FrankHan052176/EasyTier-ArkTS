import { NetworkConfig } from "./protobuf/api_manage";
import { Logger, LogLocate } from "./util/Logger";
import easytier from "easytier-ohrs"
import { NetworkConfigTypeMap } from "./protobuf/proto-type-map";
import { util } from "@kit.ArkTS";

const ignoreField: Set<string> = new Set([
  "networkingMethod", "publicServerUrl", "advancedSettings", "devName",
  "mtu", "quicListenPort", "bindDevice", "enableRelayNetworkWhitelist", "enableManualRoutes", "instanceId"])
type fieldType = string | ConfigField[]

export class ConfigField {
  name: string
  type: fieldType
  constructor(name: string, type: fieldType) {
    this.name = name
    this.type = type
  }
}

@LogLocate("ContentUtil")
export class ContentUtil {
  private static logStruct: boolean = false
  public static fieldList: ConfigField[] = []
  public static flagField: ConfigField = new ConfigField("flags_switch", [])
  public static combinedField: Record<string, string[]> = {
    "virtual_ipv4_dhcp": ["dhcp", "virtual_ipv4"],
    "identity": ["networkName", "networkSecret"],
    "vpnPortal": ["enableVpnPortal",  "vpnPortalListenPort", "vpn_portal_client_network"],
    "socks5": ["enableSocks5", "socks5Port"],
    "virtual_ipv4": ["virtualIpv4", "networkLength"],
    "vpn_portal_client_network": ["vpnPortalClientNetworkAddr", "vpnPortalClientNetworkLen"]
  }
  public static renamedField: Record<string, string> = {
    "routes": "manualRoutes",
  }
  public static overrideFieldType: Record<string, string> = {
    "virtual_ipv4": "cidr",
    "virtualIpv4": "cidr_ip",
    "networkLength": "cidr_mask",
    "vpnPortalListenPort": "port",
    "vpn_portal_client_network": "cidr",
    "vpnPortalClientNetworkAddr": "cidr_ip",
    "vpnPortalClientNetworkLen": "cidr_mask",
    "socks5Port": "port",
    "peerUrls": "peer[]",
    "proxyCidrs": "cidr[]",
    "listenerUrls": "listener[]",
    "manualRoutes": "route[]",
    "exitNodes": "ip[]",
    "mappedListeners": "mappedListener[]",
    "portForwards": "port_forward[]"
  }
  public static fieldTag: Record<string, string> = {
    "dhcp": "inverse",
    "vpnPortal": "hidable",
    "socks5": "hidable",
    "networkName": "topFieldName username enter_next",
    "networkSecret": "topFieldName password",
    "identity": "hideTitle"
  }

  public static hasTag(fieldName: string, tag: string): boolean {
    return (ContentUtil.fieldTag[fieldName] ?? "").includes(tag)
  }

  public static safeFieldName(value: string): string {
    for (const [key, rename] of Object.entries(this.renamedField)) {
      if (rename == value) {
        return key;
      }
    }
    return value
  }

  private static findCombinedFieldKey(value: string): string | undefined {
    for (const [key, fields] of Object.entries(this.combinedField)) {
      if (fields.includes(value)) {
        return key;
      }
    }
    return undefined;
  }

  private static getFieldType(field: string): string {
    return this.overrideFieldType[field] || NetworkConfigTypeMap[field]
  }

  public static getDefaultConfig(): NetworkConfig {
    let cfg = NetworkConfig.fromJSON(easytier.defaultNetworkConfig())
    cfg.enableRelayNetworkWhitelist = true
    cfg.enableManualRoutes = true
    return cfg
  }

  public static initConfigFields() {
    let added: Set<string> = new Set()
    Object.entries(this.getDefaultConfig()).forEach((pair:[string, any]) => {
      let field = this.renamedField[pair[0]] || pair[0]
      if (ignoreField.has(field)) {}
      else {
        let singleField = this.findCombinedFieldKey(field) || field
        let isCombinedField = this.findCombinedFieldKey(singleField) !== undefined
        if (added.has(singleField) || isCombinedField) {}
        else {
          if (singleField === field) {
            let type = this.getFieldType(singleField)
            if (type === "boolean") {
              if (!added.has("flags")) {
                added.add("flags")
                this.fieldList.push(this.flagField)
              }
              (this.flagField.type as ConfigField[]).push(new ConfigField(singleField, type))
            }else {
              this.fieldList.push(new ConfigField(singleField, type))
            }
            if(this.logStruct) Logger.debug("init Field "+singleField+": "+this.getFieldType(singleField)+"=", ContentUtil)
          }else {
            let combineFields: ConfigField[] = []
            if(this.logStruct) Logger.debug("init Field "+singleField, ContentUtil)
            for (const child_field of this.combinedField[singleField]) {
              combineFields.push(new ConfigField(child_field, this.getFieldType(child_field)))
              if(this.logStruct) Logger.debug("init Field   |---"+child_field+": "+this.getFieldType(child_field), ContentUtil)
            }
            this.fieldList.push(new ConfigField(singleField, combineFields))
          }
          added.add(singleField)
        }
      }
    })
  }
}