import easytier from 'easytier-ohrs'
import { COMBINED_CONFIG_FIELDS, getCombinedConfigChildren, IGNORED_CONFIG_FIELDS } from './SchemaLayout'

type FieldType = string | ConfigField[]

const OVERRIDE_FIELD_TYPES: Record<string, string> = {
  virtual_ipv4: 'cidr_ip',
  network_length: 'cidr_mask',
  vpn_portal_listen_port: 'port',
  vpn_portal_client_network_addr: 'cidr_ip',
  vpn_portal_client_network_len: 'cidr_mask',
  socks5_port: 'port',
  peer_urls: 'peer[]',
  proxy_cidrs: 'cidr[]',
  listener_urls: 'listener[]',
  routes: 'route[]',
  exit_nodes: 'ip[]',
  relay_network_whitelist: 'network_name[]',
  mapped_listeners: 'mapped_listener[]',
  port_forwards: 'port_forward[]',
  data_compress_algo: 'number'
}

export class ConfigField {
  name: string
  type: FieldType
  path: string[]

  constructor(name: string, type: FieldType, path?: string[]) {
    this.name = name
    this.type = type
    this.path = path ?? [name]
  }
}

enum FieldCategory {
  BASIC = 0,
  FLAGS = 1,
  ADVANCED = 2,
  OTHER = 3
}

const FIELD_CATEGORY: Record<string, FieldCategory> = {
  basic_setting: FieldCategory.BASIC,
  peer_urls: FieldCategory.BASIC,
  flags_switch: FieldCategory.FLAGS,
  proxy_cidrs: FieldCategory.ADVANCED,
  listener_urls: FieldCategory.ADVANCED,
  routes: FieldCategory.ADVANCED,
  exit_nodes: FieldCategory.ADVANCED,
  mapped_listeners: FieldCategory.ADVANCED,
  relay_network_whitelist: FieldCategory.ADVANCED,
  port_forwards: FieldCategory.ADVANCED
}

function getFieldCategory(fieldName: string): FieldCategory {
  return FIELD_CATEGORY[fieldName] ?? FieldCategory.OTHER
}

function findCombinedFieldKey(value: string): string | undefined {
  for (const [key, fields] of Object.entries(COMBINED_CONFIG_FIELDS)) {
    if (fields.includes(value)) {
      return key
    }
  }
  return undefined
}

function findTopCombinedParent(fieldName: string): string | undefined {
  const parent = findCombinedFieldKey(fieldName)
  if (!parent) {
    return undefined
  }
  return findTopCombinedParent(parent) ?? parent
}

export class ConfigFieldRegistry {
  fieldList: ConfigField[] = []
  basicFields: ConfigField[] = []
  flagField: ConfigField = new ConfigField('flags_switch', [])
  advancedFields: ConfigField[] = []
  otherFields: ConfigField[] = []

  init() {
    if (this.fieldList.length > 0) {
      return
    }
    const schema = easytier.getNetworkConfigSchema()
    const added = new Set<string>()
    for (const schemaField of schema.children) {
      const fieldName = schemaField.name
      if (IGNORED_CONFIG_FIELDS.has(fieldName)) {
        continue
      }
      const top = findTopCombinedParent(fieldName)
      if (top) {
        if (!added.has(top)) {
          added.add(top)
          this.fieldList.push(new ConfigField(top, this.buildCombinedField(top)))
        }
        continue
      }
      const type = this.getFieldType(schemaField, [fieldName])
      if (type === 'boolean') {
        if (!added.has('flags')) {
          added.add('flags')
          this.fieldList.push(this.flagField)
        }
        ;(this.flagField.type as ConfigField[]).push(new ConfigField(fieldName, type, [fieldName]))
      } else {
        this.fieldList.push(new ConfigField(fieldName, type, [fieldName]))
      }
      added.add(fieldName)
    }
    this.fieldList.sort((a, b) => getFieldCategory(a.name) - getFieldCategory(b.name)).forEach((field) => {
      switch (getFieldCategory(field.name)) {
        case FieldCategory.BASIC:
          this.basicFields.push(field)
          break
        case FieldCategory.ADVANCED:
          this.advancedFields.push(field)
          break
        case FieldCategory.OTHER:
          this.otherFields.push(field)
          break
      }
    })
  }

  private getFieldType(field: easytier.NetworkConfigSchema, path: string[]): FieldType {
    if (OVERRIDE_FIELD_TYPES[field.name]) {
      return OVERRIDE_FIELD_TYPES[field.name]
    }
    if (field.children.length > 0 && field.valueKind === 'object') {
      return field.children.map((child) => this.schemaFieldToConfigField(child, path))
    }
    if (field.semanticType) {
      return field.semanticType
    }
    return field.valueKind
  }

  private buildCombinedField(parent: string): ConfigField[] {
    const children = getCombinedConfigChildren(parent)
    const result: ConfigField[] = []
    for (const child of children) {
      if (COMBINED_CONFIG_FIELDS[child]) {
        result.push(new ConfigField(child, this.buildCombinedField(child)))
        continue
      }
      const schemaField = easytier.getNetworkConfigSchema().children.find((value) => value.name === child)
      if (schemaField) {
        result.push(this.schemaFieldToConfigField(schemaField, []))
      }
    }
    return result
  }

  private schemaFieldToConfigField(field: easytier.NetworkConfigSchema, parentPath?: string[]): ConfigField {
    const path = [...(parentPath ?? []), field.name]
    return new ConfigField(field.name, this.getFieldType(field, path), path)
  }
}

export const configFieldRegistry = new ConfigFieldRegistry()
