import { NetworkConfig, NetworkingMethod } from "./protobuf/api_manage";
import { Logger, LogLocate } from "./util/Logger";
import easytier from "easytier-ohrs"
import { NetworkConfigTypeMap } from "./protobuf/proto-type-map";
import { util } from "@kit.ArkTS";

const ignoreField: Set<string> = new Set([
  "networking_method", "public_server_url", "advanced_settings", "dev_name",
  "mtu", "quic_listen_port", "bind_device", "enable_relay_network_whitelist", "enable_manual_routes", "instance_id"])
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
    "virtual_ipv4_dhcp": ["dhcp", "virtual_ipv4_cidr"],
    "identity": ["network_name", "network_secret"],
    "vpn_portal": ["enable_vpn_portal",  "vpn_portal_listen_port", "vpn_portal_client_network"],
    "socks5": ["enable_socks5", "socks5_port"],
    "virtual_ipv4_cidr": ["virtual_ipv4", "network_length"],
    "vpn_portal_client_network": ["vpn_portal_client_network_addr", "vpn_portal_client_network_len"]
  }
  public static renamedField: Record<string, string> = {
    "routes": "manual_routes",
  }
  public static overrideFieldType: Record<string, string> = {
    "virtual_ipv4_cidr": "cidr",
    "virtual_ipv4": "cidr_ip",
    "network_length": "cidr_mask",
    "vpn_portal_listen_port": "port",
    "vpn_portal_client_network": "cidr",
    "vpn_portal_client_network_addr": "cidr_ip",
    "vpn_portal_client_network_len": "cidr_mask",
    "socks5_port": "port",
    "peer_urls": "peer[]",
    "proxy_cidrs": "cidr[]",
    "listener_urls": "listener[]",
    "manual_routes": "route[]",
    "exit_nodes": "ip[]",
    "mapped_listeners": "mappedListener[]",
    "port_forwards": "port_forward[]"
  }
  public static fieldTag: Record<string, string> = {
    "dhcp": "inverse",
    "vpn_portal": "hidable",
    "socks5": "hidable",
    "hostname": "suggest",
    "network_name": "topFieldName username enter_next",
    "network_secret": "topFieldName password",
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

  public static getDefaultConfig(hostname: string): NetworkConfig {
    let cfg = NetworkConfig.fromJSON(easytier.defaultNetworkConfig())
    cfg.networking_method = 1
    cfg.enable_relay_network_whitelist = true
    cfg.enable_manual_routes = true
    cfg.dhcp = true
    cfg.virtual_ipv4 = "10.0.0.1"
    cfg.network_length = 24
    cfg.hostname = hostname
    cfg.network_name = "easytier"
    cfg.network_secret = ""
    cfg.multi_thread = true
    return cfg
  }

  public static initConfigFields() {
    let added: Set<string> = new Set()
    Object.entries(this.getDefaultConfig("")).forEach((pair:[string, any]) => {
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