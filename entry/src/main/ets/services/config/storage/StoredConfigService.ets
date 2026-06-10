import easytier from 'easytier-ohrs'
import { JSON, taskpool } from '@kit.ArkTS'
import { getDefaultConfig } from '../../../config/defaults/ConfigDefaults'
import { ConfigFieldValue, ConfigJson } from '../../../config/schema/SchemaConfig'
import { EventHelper } from '../../../util/EventHelper'
import { RemoteManageService } from '../../remote/RemoteManageService'

interface FieldLoadWorkerResult {
  field: string
  value: ConfigFieldValue
  found: boolean
  rawLength: number
  nativeMs: number
  parseMs: number
  totalMs: number
}

let editingConfigCacheId: string | undefined = undefined
let editingConfigCacheStoreKey: string = 'local'
let editingConfigCache: ConfigJson | undefined = undefined
let editingConfigRevision: number = 0
let editingConfigDirtyFields: Set<string> = new Set()
const DEFAULT_CONFIG_FALLBACK: ConfigJson = getDefaultConfig('')

export interface EditingConfigStoreRef {
  source: string
  remoteSessionId?: string
  remoteDeviceName?: string
}

let editingConfigStoreRef: EditingConfigStoreRef = {
  source: 'local'
}

export const EDITING_CONFIG_REFRESH_EVENT = 'editing_config_refresh'
export const EDITING_CONFIG_FIELD_REFRESH_EVENT_PREFIX = 'editing_config_field_refresh:'

export function getEditingConfigFieldRefreshEvent(field: string): string {
  return EDITING_CONFIG_FIELD_REFRESH_EVENT_PREFIX + field
}

function currentEditingStoreKey(): string {
  if (editingConfigStoreRef.source === 'remote') {
    return `remote:${editingConfigStoreRef.remoteSessionId ?? ''}`
  }
  return 'local'
}

export function setEditingConfigStoreRef(ref?: EditingConfigStoreRef): void {
  const nextRef: EditingConfigStoreRef = ref ?? { source: 'local' }
  const oldKey = currentEditingStoreKey()
  editingConfigStoreRef = nextRef
  if (oldKey !== currentEditingStoreKey()) {
    editingConfigCacheId = undefined
    editingConfigCache = undefined
    editingConfigLoadedFields.clear()
    editingConfigInFlightFields.clear()
    editingConfigDirtyFields.clear()
  }
}

export function resetEditingConfigStoreRef(): void {
  setEditingConfigStoreRef({ source: 'local' })
}

export function getEditingConfigStoreRef(): EditingConfigStoreRef {
  return editingConfigStoreRef
}

export function isEditingRemoteConfig(): boolean {
  return editingConfigStoreRef.source === 'remote'
}

export function isEditingConfigTarget(editingId: string | undefined): boolean {
  if (!editingId || editingId.length === 0) {
    return false
  }
  return editingConfigCacheId === editingId && editingConfigCacheStoreKey === currentEditingStoreKey()
}

function editingFieldRequestKey(storeKey: string, editingId: string, field: string): string {
  return `${storeKey}:${editingId}:${field}`
}

@Concurrent
async function loadStoredConfigFieldsWorker(uuid: string, fields: string[]): Promise<FieldLoadWorkerResult[]> {
  const results: FieldLoadWorkerResult[] = []
  fields.forEach((field) => {
    const totalStart = Date.now()
    const nativeStart = Date.now()
    const rawValue = easytier.getConfigField(uuid, field)
    const nativeMs = Date.now() - nativeStart
    if (!rawValue) {
      results.push({
        field,
        value: undefined,
        found: false,
        rawLength: 0,
        nativeMs,
        parseMs: 0,
        totalMs: Date.now() - totalStart
      })
      return
    }
    const rawText = rawValue as string
    const parseStart = Date.now()
    let value: ConfigFieldValue = undefined
    try {
      value = JSON.parse(rawText)
    } catch (_) {
      value = undefined
    }
    results.push({
      field,
      value,
      found: true,
      rawLength: rawText.length,
      nativeMs,
      parseMs: Date.now() - parseStart,
      totalMs: Date.now() - totalStart
    })
  })
  return results
}

let editingConfigLoadedFields: Set<string> = new Set()
let editingConfigInFlightFields: Map<string, Promise<void>> = new Map()

export interface StoredConfigMetaLite {
  configId: string
  displayName: string
}

export function getStoredConfig(uuid: string): ConfigJson | undefined {
  if (isEditingRemoteConfig()) {
    return editingConfigCacheId === uuid && editingConfigCacheStoreKey === currentEditingStoreKey()
      ? editingConfigCache
      : undefined
  }
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
  if (isEditingRemoteConfig()) {
    return RemoteManageService.getConfigName(uuid) ?? undefined
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
  const storeKey = currentEditingStoreKey()
  const sameConfig = editingConfigCacheId === editingId && editingConfigCacheStoreKey === storeKey
  editingConfigCacheId = editingId
  editingConfigCacheStoreKey = storeKey
  editingConfigCache = config
  if (!sameConfig || !config) {
    editingConfigLoadedFields.clear()
    editingConfigInFlightFields.clear()
    editingConfigDirtyFields.clear()
  }
}

export function prepareEditingConfig(editingId: string | undefined): ConfigJson | undefined {
  const storeKey = currentEditingStoreKey()
  if (editingConfigCacheId === editingId && editingConfigCacheStoreKey === storeKey && editingConfigCache) {
    if (editingId && editingId.length > 0) {
      editingConfigCache.instance_id = editingId
    }
    return editingConfigCache
  }
  editingConfigCacheId = editingId
  editingConfigCacheStoreKey = storeKey
  editingConfigCache = getDefaultConfig('')
  if (editingId && editingId.length > 0) {
    editingConfigCache.instance_id = editingId
  }
  editingConfigLoadedFields.clear()
  editingConfigInFlightFields.clear()
  editingConfigDirtyFields.clear()
  return editingConfigCache
}

export function refreshEditingConfig(editingId: string | undefined): ConfigJson | undefined {
  return prepareEditingConfig(editingId)
}

export async function refreshEditingConfigAsync(editingId: string | undefined): Promise<ConfigJson | undefined> {
  return prepareEditingConfig(editingId)
}

export function clearEditingConfigCache(editingId?: string): void {
  if (!editingId || (editingConfigCacheId === editingId && editingConfigCacheStoreKey === currentEditingStoreKey())) {
    editingConfigCacheId = undefined
    editingConfigCacheStoreKey = currentEditingStoreKey()
    editingConfigCache = undefined
    editingConfigLoadedFields.clear()
    editingConfigInFlightFields.clear()
    editingConfigDirtyFields.clear()
  }
}

export function markEditingConfigFieldDirty(editingId: string | undefined, field: string | undefined): void {
  if (!editingId || editingId.length === 0 || !field || field.length === 0 || editingConfigCacheId !== editingId ||
    editingConfigCacheStoreKey !== currentEditingStoreKey()) {
    return
  }
  editingConfigDirtyFields.add(field)
}

export function getEditingConfigRevision(): number {
  return editingConfigRevision
}

function publishEditingConfigRefresh(editingId: string | undefined): void {
  editingConfigRevision += 1
  EventHelper.emitterPublish(EDITING_CONFIG_REFRESH_EVENT, {
    data: {
      configId: editingId ?? '',
      revision: editingConfigRevision
    }
  })
}

function publishEditingConfigFieldRefresh(editingId: string | undefined, field: string): void {
  EventHelper.emitterPublish(getEditingConfigFieldRefreshEvent(field), {
    data: {
      configId: editingId ?? '',
      field
    }
  })
}

function setEditingFieldValue(field: string, value: ConfigFieldValue): void {
  if (!editingConfigCache) {
    editingConfigCache = getDefaultConfig('')
  }
  editingConfigCache[field] = value === undefined
    ? cloneConfigFieldValue(DEFAULT_CONFIG_FALLBACK[field] as ConfigFieldValue)
    : value
}

function cloneConfigFieldValue(value: ConfigFieldValue): ConfigFieldValue {
  if (value === undefined || value === null || typeof value !== 'object') {
    return value
  }
  try {
    return JSON.parse(JSON.stringify(value)) as ConfigFieldValue
  } catch (_) {
    return undefined
  }
}

export function areEditingFieldsLoaded(editingId: string | undefined, fields: string[]): boolean {
  if (!editingId || editingId.length === 0) {
    return true
  }
  if (editingConfigCacheId !== editingId || editingConfigCacheStoreKey !== currentEditingStoreKey() ||
    editingConfigCache === undefined) {
    return false
  }
  return fields.every((field) => editingConfigLoadedFields.has(field) || editingConfigDirtyFields.has(field))
}

export function canSyncEditingConfigField(editingId: string | undefined, field: string | undefined): boolean {
  if (!editingId || editingId.length === 0 || !field || field.length === 0) {
    return true
  }
  if (editingConfigCacheId !== editingId || editingConfigCacheStoreKey !== currentEditingStoreKey()) {
    return true
  }
  return editingConfigLoadedFields.has(field) || editingConfigDirtyFields.has(field)
}

export async function ensureEditingFieldsAsync(editingId: string | undefined, fields: string[]): Promise<void> {
  if (!editingConfigCache || editingConfigCacheId !== editingId) {
    prepareEditingConfig(editingId)
  }
  if (!editingId || editingId.length === 0 || fields.length === 0) {
    return
  }
  const uniqueFields: string[] = []
  fields.forEach((field) => {
    if (field.length > 0 && uniqueFields.indexOf(field) < 0) {
      uniqueFields.push(field)
    }
  })
  const storeKey = currentEditingStoreKey()
  const remoteSessionId = editingConfigStoreRef.remoteSessionId
  const pendingFields = uniqueFields.filter((field) => {
    return !editingConfigLoadedFields.has(field) && !editingConfigDirtyFields.has(field)
  })
  if (pendingFields.length === 0) {
    return
  }
  const promises: Promise<void>[] = []
  const loadFields: string[] = []
  pendingFields.forEach((field) => {
    const inFlight = editingConfigInFlightFields.get(editingFieldRequestKey(storeKey, editingId, field))
    if (inFlight) {
      promises.push(inFlight)
      return
    }
    loadFields.push(field)
  })
  if (loadFields.length > 0) {
    const loadPromise = loadEditingFieldsBatchAsync(editingId, loadFields, storeKey, remoteSessionId)
    loadFields.forEach((field) => {
      editingConfigInFlightFields.set(editingFieldRequestKey(storeKey, editingId, field), loadPromise)
    })
    promises.push(loadPromise)
  }
  await Promise.all(promises)
}

async function loadEditingFieldsBatchAsync(editingId: string, fields: string[], storeKey: string,
  remoteSessionId?: string): Promise<void> {
  const promise: Promise<void> = (async () => {
    try {
      let results: FieldLoadWorkerResult[]
	      if (storeKey.startsWith('remote:')) {
	        const remoteResult = await RemoteManageService.getConfigFields(editingId, fields, remoteSessionId)
	        if (remoteResult.values.length < fields.length) {
	          throw new Error('remote field response incomplete')
	        }
	        results = remoteResult.values.map((item) => {
          const totalStart = Date.now()
          let value: ConfigFieldValue = undefined
          let parseMs = 0
          if (item.found && item.rawValue !== undefined) {
            const parseStart = Date.now()
            try {
              value = JSON.parse(item.rawValue) as ConfigFieldValue
            } catch (_) {
              value = undefined
            }
            parseMs = Date.now() - parseStart
          }
          return {
            field: item.field,
            value,
            found: item.found,
            rawLength: item.rawValue?.length ?? 0,
            nativeMs: 0,
            parseMs,
            totalMs: Date.now() - totalStart
          } as FieldLoadWorkerResult
        })
      } else {
        results = (await taskpool.execute(loadStoredConfigFieldsWorker, editingId, fields)) as FieldLoadWorkerResult[]
      }
      if (editingConfigCacheId !== editingId || editingConfigCacheStoreKey !== storeKey) {
        return
      }
      results.forEach((result) => {
        const field = result.field
        if (editingConfigDirtyFields.has(field)) {
          return
        }
        if (result.found) {
          setEditingFieldValue(field, result.value)
        }
        editingConfigLoadedFields.add(field)
        publishEditingConfigFieldRefresh(editingId, field)
      })
    } catch (_) {
      throw new Error('load editing fields failed')
    } finally {
      fields.forEach((field) => {
        editingConfigInFlightFields.delete(editingFieldRequestKey(storeKey, editingId, field))
      })
    }
  })()
  await promise
}

export function getEditingConfig(editingId: string | undefined): ConfigJson | undefined {
  if (!editingId || editingId.length === 0) {
    return editingConfigCache ?? getDefaultConfig('')
  }
  if (editingConfigCacheId !== editingId || editingConfigCacheStoreKey !== currentEditingStoreKey() ||
    !editingConfigCache) {
    return prepareEditingConfig(editingId)
  }
  return editingConfigCache
}
