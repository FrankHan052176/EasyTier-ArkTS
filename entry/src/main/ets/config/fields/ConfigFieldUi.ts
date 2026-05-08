const VAULT_FIELDS: ReadonlySet<string> = new Set(['identity'])

const FIELD_I18N_ALIASES: Record<string, string> = {
  routes: 'manual_routes',
  virtual_ipv4_comp: 'virtual_ipv4',
  dhcp: 'virtual_ipv4_dhcp'
}

const FIELD_TAGS: Record<string, string> = {
  basic_setting: 'useDivider',
  dhcp: 'inverse rightFieldName',
  hostname: 'useHostname',
  network_name: 'topFieldName username enter_next',
  network_secret: 'topFieldName password',
  identity: 'hideTitle',
  virtual_ip: 'insideName',
  vpn_portal_client_network: 'outsideName',
  encryption_algorithm: 'leftFieldName',
  local_private_key: 'leftFieldName',
  local_public_key: 'leftFieldName'
}

export function getFieldI18nKey(fieldName: string): string {
  return FIELD_I18N_ALIASES[fieldName] ?? fieldName
}

export function hasFieldTag(fieldName: string, tag: string): boolean {
  return (FIELD_TAGS[fieldName] ?? '').includes(tag)
}

export function isVaultField(fieldName: string): boolean {
  return VAULT_FIELDS.has(fieldName)
}
