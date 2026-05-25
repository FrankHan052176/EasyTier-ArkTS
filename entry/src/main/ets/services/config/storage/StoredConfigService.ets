import easytier from 'easytier-ohrs'
import { JSON } from '@kit.ArkTS'
import { getDefaultConfig } from '../../../config/defaults/ConfigDefaults'
import { ConfigJson } from '../../../config/schema/SchemaConfig'

let editingConfigCacheId: string | undefined = undefined
let editingConfigCache: ConfigJson | undefined = undefined

export interface StoredConfigMetaLite {
  configId: string
  displayName: string
}

export function getStoredConfig(uuid: string): ConfigJson | undefined {
  const rawConfig = easytier.getConfig(uuid)
  if (!rawConfig) {
    return undefined
  }
  try {
    return JSON.parse(rawConfig as string) as ConfigJson
  } catch (_) {
    return undefined
  }
}

export function getStoredConfigName(uuid: string | undefined): string | undefined {
  if (!uuid || uuid.length === 0) {
    return undefined
  }
  return easytier.getConfigDisplayNameById(uuid) ?? undefined
}

export function getStoredConfigLabel(uuid: string | undefined, emptyLabel: string = ''): string {
  if (!uuid || uuid.length === 0) {
    return emptyLabel
  }
  const name = getStoredConfigName(uuid)
  return name && name.length > 0 ? name : uuid
}

export function listStoredConfigs(): StoredConfigMetaLite[] {
  try {
    const rawEntries = JSON.parse(easytier.listConfigs()) as StoredConfigMetaLite[]
    return (rawEntries ?? []).map((item) => {
      const configId = item.configId
      const displayName = item.displayName ?? configId
      const entry: StoredConfigMetaLite = { configId, displayName }
      return entry
    }).filter((item) => item.configId.length > 0)
  } catch (_) {
    return []
  }
}

export function cacheEditingConfig(editingId: string | undefined, config: ConfigJson | undefined): void {
  editingConfigCacheId = editingId
  editingConfigCache = config
}

export function refreshEditingConfig(editingId: string | undefined): ConfigJson | undefined {
  if (!editingId || editingId.length === 0) {
    editingConfigCacheId = undefined
    editingConfigCache = undefined
    return getDefaultConfig('')
  }
  editingConfigCacheId = editingId
  editingConfigCache = getStoredConfig(editingId) ?? getDefaultConfig('')
  return editingConfigCache
}

export function clearEditingConfigCache(editingId?: string): void {
  if (!editingId || editingConfigCacheId === editingId) {
    editingConfigCacheId = undefined
    editingConfigCache = undefined
  }
}

export function getEditingConfig(editingId: string | undefined): ConfigJson | undefined {
  if (!editingId || editingId.length === 0) {
    editingConfigCacheId = undefined
    editingConfigCache = undefined
    return getDefaultConfig('')
  }
  if (editingConfigCacheId !== editingId || !editingConfigCache) {
    return refreshEditingConfig(editingId)
  }
  return editingConfigCache
}
