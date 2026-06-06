import easytier from 'easytier-ohrs'
import { ConfigJson, ConfigFieldValue } from './config/schema/SchemaConfig'
import { cacheEditingConfig, canSyncEditingConfigField, markEditingConfigFieldDirty } from './services/config/storage/StoredConfigService'
import { isCloudResetting } from './services/cloud/CloudMutationGate'
import { EventHelper } from './util/EventHelper'

export const CLOUD_CONFIG_CHANGED_EVENT = 'cloud_config_changed'

function getTopLevelValue(config: ConfigJson, field: string): ConfigFieldValue {
  return config[field] as ConfigFieldValue
}

function setTopLevelValue(config: ConfigJson, field: string, value: ConfigFieldValue): void {
  config[field] = value
}

export function getFieldPathValue(config: ConfigJson, path: string[]): ConfigFieldValue {
  if (path.length === 1) {
    return getTopLevelValue(config, path[0])
  }
  let current: ConfigFieldValue = getTopLevelValue(config, path[0])
  for (let index = 1; index < path.length; index++) {
    if (current === undefined || current === null || typeof current !== 'object' || Array.isArray(current)) {
      return undefined
    }
    current = (current as ESObject)[path[index]] as ConfigFieldValue
  }
  return current
}

export function setFieldPathValue(config: ConfigJson, path: string[], value: ConfigFieldValue): void {
  if (path.length === 1) {
    setTopLevelValue(config, path[0], value)
    return
  }
  let current: ESObject = config
  for (let index = 0; index < path.length - 1; index++) {
    const part = path[index]
    let next: ConfigFieldValue = current[part] as ConfigFieldValue
    if (next === undefined || next === null || typeof next !== 'object' || Array.isArray(next)) {
      next = {}
      current[part] = next
    }
    current = next as ESObject
  }
  current[path[path.length - 1]] = value
}

export function syncTopLevelField(configId: string | undefined, field: string | undefined, config: ConfigJson): boolean {
  if (!configId || configId.length === 0 || !field || field.length === 0 || isCloudResetting()) {
    return false
  }
  if (!canSyncEditingConfigField(configId, field)) {
    return false
  }
  const value: ConfigFieldValue = getTopLevelValue(config, field)
  const ok = easytier.setConfigField(configId, field, JSON.stringify(value ?? null))
  if (ok) {
    markEditingConfigFieldDirty(configId, field)
    cacheEditingConfig(configId, config)
    EventHelper.emitterPublish(CLOUD_CONFIG_CHANGED_EVENT)
  }
  return ok
}

export function syncFieldPath(configId: string | undefined, path: string[], config: ConfigJson): boolean {
  return syncTopLevelField(configId, path[0], config)
}

export function ensureKernelConfig(configId: string, displayName: string): boolean {
  if (isCloudResetting()) {
    return false
  }
  if (easytier.getConfig(configId)) {
    return true
  }
  return easytier.createConfig(configId, displayName)
}

export function syncWholeConfig(configId: string, displayName: string, config: ConfigJson): boolean {
  if (isCloudResetting()) {
    return false
  }
  if (!ensureKernelConfig(configId, displayName)) {
    return false
  }
  const ok = easytier.saveConfig(configId, displayName, JSON.stringify(config))
  if (!ok) {
    return false
  }
  cacheEditingConfig(configId, config)
  EventHelper.emitterPublish(CLOUD_CONFIG_CHANGED_EVENT)
  return true
}
