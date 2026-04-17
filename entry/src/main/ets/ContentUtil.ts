import { NetworkConfig } from './protobuf/api_manage';
import { LogLocate } from './util/Logger';
import easytier from 'easytier-ohrs';
import { NetworkConfigTypeMap } from './protobuf/proto-type-map';
import { deviceInfo } from '@kit.BasicServicesKit';

const ignoreField: Set<string> = new Set([
  "networking_method", "public_server_url", "advanced_settings", "dev_name",
  "mtu", "quic_listen_port", "bind_device", "enable_relay_network_whitelist", "enable_manual_routes", "instance_id", "credential_file"])
const vaultFields: Set<string> = new Set(["identity"])
type fieldType = string | ConfigField[]

export class ConfigField {
  name: string
  type: fieldType

  constructor(name: string, type: fieldType) {
    this.name = name
    this.type = type
  }
}

export enum FieldCategory {
  BASIC = 0,
  FLAGS = 1,
  ADVANCED = 2,
  OTHER = 3
}

@LogLocate("ContentUtil")
export class ContentUtil {
  public static fieldList: ConfigField[] = []
  public static basicFields: ConfigField[] = []
  public static flagField: ConfigField = new ConfigField("flags_switch", [])
  public static advancedFields: ConfigField[] = []
  public static otherFields: ConfigField[] = []
  public static combinedField: Record<string, string[]> = {
    "basic_setting": ["virtual_ipv4_comp", "hostname", "identity"],
    "algorithm_setting": ["data_compress_algo", "encryption_algorithm"],
    "virtual_ipv4_comp": ["dhcp", "virtual_ip"],
    "identity": ["network_name", "network_secret"],
    "vpn_portal": ["enable_vpn_portal", "vpn_portal_listen_port", "vpn_portal_client_network"],
    "socks5": ["enable_socks5", "socks5_port"],
    "virtual_ip": ["virtual_ipv4", "network_length"],
    "vpn_portal_client_network": ["vpn_portal_client_network_addr", "vpn_portal_client_network_len"]
  }
  public static renamedField: Record<string, string> = {
    "routes": "manual_routes",
    "virtual_ipv4_comp": "virtual_ipv4",
    "dhcp": "virtual_ipv4_dhcp"
  }
  public static overrideFieldType: Record<string, string> = {
    "virtual_ipv4": "cidr_ip",
    "network_length": "cidr_mask",
    "vpn_portal_listen_port": "port",
    "vpn_portal_client_network_addr": "cidr_ip",
    "vpn_portal_client_network_len": "cidr_mask",
    "socks5_port": "port",
    "peer_urls": "peer[]",
    "proxy_cidrs": "cidr[]",
    "listener_urls": "listener[]",
    "routes": "route[]",
    "exit_nodes": "ip[]",
    "relay_network_whitelist": "network_name[]",
    "mapped_listeners": "mapped_listener[]",
    "port_forwards": "port_forward[]",
    "data_compress_algo": "number"
  }
  public static fieldTag: Record<string, string> = {
    "basic_setting": "useDivider",
    "dhcp": "inverse rightFieldName",
    "vpn_portal": "",
    "socks5": "",
    "hostname": "useHostname",
    "network_name": "topFieldName username enter_next",
    "network_secret": "topFieldName password",
    "identity": "hideTitle",
    "virtual_ip": "insideName",
    "vpn_portal_client_network": "outsideName",
    "encryption_algorithm": "leftFieldName"
  }

  private static fieldCategory: Record<string, FieldCategory> = {
    "basic_setting": FieldCategory.BASIC,
    "peer_urls": FieldCategory.BASIC,
    "flags_switch": FieldCategory.FLAGS,
    "proxy_cidrs": FieldCategory.ADVANCED,
    "listener_urls": FieldCategory.ADVANCED,
    "routes": FieldCategory.ADVANCED,
    "exit_nodes": FieldCategory.ADVANCED,
    "mapped_listeners": FieldCategory.ADVANCED,
    "relay_network_whitelist": FieldCategory.ADVANCED,
    "port_forwards": FieldCategory.ADVANCED
  }

  public static getFieldCategory(fieldName: string): FieldCategory {
    return ContentUtil.fieldCategory[fieldName] ?? FieldCategory.OTHER
  }

  public static hasTag(fieldName: string, tag: string): boolean {
    return (ContentUtil.fieldTag[fieldName] ?? "").includes(tag)
  }

  public static safeFieldName(value: string): string {
    return value
  }

  public static isVaultField(value: string): boolean {
    return vaultFields.has(value)
  }

  public static getDefaultConfig(hostname: string): NetworkConfig {
    let cfg = NetworkConfig.fromJSON(deviceInfo.productModel !== "emulator" ? easytier.defaultNetworkConfig() : "{}")
    cfg.networking_method = 1
    cfg.public_server_url = ""
    cfg.enable_relay_network_whitelist = true
    cfg.enable_manual_routes = true
    cfg.dhcp = true
    cfg.virtual_ipv4 = "10.0.0.1"
    cfg.network_length = 24
    cfg.hostname = hostname
    cfg.network_name = "easytier"
    cfg.network_secret = ""
    cfg.multi_thread = true
    cfg.vpn_portal_listen_port = 22022
    cfg.vpn_portal_client_network_addr = "10.0.1.0"
    cfg.vpn_portal_client_network_len = 24
    cfg.socks5_port = 1080
    return cfg
  }

  public static initConfigFields() {
    let added = new Set<string>()
    for (const field of Object.keys(this.getDefaultConfig(""))) {
      if (ignoreField.has(field)) {
        continue
      }
      const top = this.findTopCombinedParent(field)
      if (top) {
        if (!added.has(top)) {
          added.add(top)
          this.fieldList.push(
            new ConfigField(top, this.buildCombinedField(top))
          )
        }
        continue
      }
      const type = this.getFieldType(field)
      if (type === "boolean") {
        if (!added.has("flags")) {
          added.add("flags")
          this.fieldList.push(this.flagField)
        }
        (this.flagField.type as ConfigField[]).push(new ConfigField(field, type))
      } else {
        this.fieldList.push(new ConfigField(field, type))
      }
      added.add(field)
    }
    this.fieldList.sort((a, b) => {
      return this.getFieldCategory(a.name) - this.getFieldCategory(b.name)
    }).forEach((field) => {
      let category = this.getFieldCategory(field.name)
      switch (category) {
        case FieldCategory.BASIC: {
          this.basicFields.push(field)
          break;
        }
        case FieldCategory.ADVANCED: {
          this.advancedFields.push(field)
          break;
        }
        case FieldCategory.OTHER: {
          this.otherFields.push(field)
          break;
        }
      }
    })
  }

  private static findCombinedFieldKey(value: string): string | undefined {
    for (const [key, fields] of Object.entries(this.combinedField)) {
      if (fields.includes(value)) {
        return key
      }
    }
    return undefined
  }

  private static getFieldType(field: string): string {
    return this.overrideFieldType[field] || NetworkConfigTypeMap[field]
  }

  private static findTopCombinedParent(field: string): string | undefined {
    const parent = this.findCombinedFieldKey(field)
    if (!parent) {
      return undefined
    }
    return this.findTopCombinedParent(parent) ?? parent
  }

  private static buildCombinedField(parent: string): ConfigField[] {
    const children = this.combinedField[parent] ?? []
    const result: ConfigField[] = []

    for (const child of children) {
      if (this.combinedField[child]) {
        result.push(new ConfigField(child, this.buildCombinedField(child)))
      } else {
        result.push(new ConfigField(child, this.getFieldType(child)))
      }
    }

    return result
  }
}