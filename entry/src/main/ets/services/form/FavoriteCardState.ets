import { Context } from '@kit.AbilityKit'
import { preferences } from '@kit.ArkData'
import { formBindingData } from '@kit.FormKit'
import { JSON } from '@kit.ArkTS'
import easytier from 'easytier-ohrs'

export const FAVORITE_CARD_REFRESH_EVENT = 'favorite_card_refresh'
export const FAVORITE_CARD_PREFERENCE_NAME = 'EasyTierCardList'

const CARD_LIST_KEY = 'card_list'
const FAVORITE_UUID_KEY = 'favorite_uuid'
const FAVORITE_NAME_KEY = 'favorite_name'
const FAVORITE_RUNNING_KEY = 'favorite_running'
const FAVORITE_UPDATED_AT_KEY = 'favorite_updated_at'

interface StoredConfigMetaLite {
  configId: string
  displayName?: string
  favorite?: boolean
}

export interface FavoriteCardSnapshot {
  favoriteUuid: string
  favoriteName: string
  favoriteRunning: boolean
  updatedAt: number
}

function getCardStore(context: Context): preferences.Preferences | undefined {
  try {
    return preferences.getPreferencesSync(context, { name: FAVORITE_CARD_PREFERENCE_NAME })
  } catch (_) {
    return undefined
  }
}

function readStoredFavorite(context: Context): FavoriteCardSnapshot | undefined {
  try {
    if (!context.filesDir || context.filesDir.length === 0 || !easytier.initConfigStore(context.filesDir)) {
      return undefined
    }
    const entries = JSON.parse(easytier.listConfigs()) as StoredConfigMetaLite[]
    const favorite = entries.find((entry) => !!entry.favorite)
    if (!favorite || !favorite.configId || favorite.configId.length === 0) {
      return {
        favoriteUuid: '',
        favoriteName: '',
        favoriteRunning: false,
        updatedAt: Date.now()
      }
    }
    return {
      favoriteUuid: favorite.configId,
      favoriteName: favorite.displayName ?? easytier.getConfigDisplayNameById(favorite.configId) ?? favorite.configId,
      favoriteRunning: false,
      updatedAt: Date.now()
    }
  } catch (_) {
    return undefined
  }
}

export function readFavoriteCardSnapshot(context: Context): FavoriteCardSnapshot {
  const store = getCardStore(context)
  let prefUuid = ''
  let prefName = ''
  let prefRunning = false
  let prefUpdatedAt = 0
  if (store) {
    try {
      prefUuid = store.getSync(FAVORITE_UUID_KEY, '').toString()
      prefName = store.getSync(FAVORITE_NAME_KEY, '').toString()
      prefRunning = Boolean(store.getSync(FAVORITE_RUNNING_KEY, false))
      prefUpdatedAt = Number(store.getSync(FAVORITE_UPDATED_AT_KEY, 0))
    } catch (_) {
      prefUuid = ''
      prefName = ''
      prefRunning = false
      prefUpdatedAt = 0
    }
  }
  const storedFavorite = readStoredFavorite(context)
  if (storedFavorite) {
    return {
      favoriteUuid: storedFavorite.favoriteUuid,
      favoriteName: storedFavorite.favoriteName,
      favoriteRunning: storedFavorite.favoriteUuid.length > 0 && storedFavorite.favoriteUuid === prefUuid ? prefRunning : false,
      updatedAt: Math.max(storedFavorite.updatedAt, prefUpdatedAt)
    }
  }
  return {
    favoriteUuid: prefUuid,
    favoriteName: prefName,
    favoriteRunning: prefRunning,
    updatedAt: prefUpdatedAt
  }
}

export function writeFavoriteCardSnapshot(context: Context, snapshot: FavoriteCardSnapshot): void {
  const store = getCardStore(context)
  if (!store) {
    return
  }
  try {
    store.putSync(FAVORITE_UUID_KEY, snapshot.favoriteUuid)
    store.putSync(FAVORITE_NAME_KEY, snapshot.favoriteName)
    store.putSync(FAVORITE_RUNNING_KEY, snapshot.favoriteRunning)
    store.putSync(FAVORITE_UPDATED_AT_KEY, snapshot.updatedAt)
    store.flushSync()
  } catch (_) {
  }
}

export function getFavoriteCardIds(context: Context): string[] {
  const store = getCardStore(context)
  if (!store) {
    return []
  }
  try {
    return store.getSync(CARD_LIST_KEY, []) as string[]
  } catch (_) {
    return []
  }
}

export function addFavoriteCardId(context: Context, formId: string): void {
  if (!formId || formId.length === 0) {
    return
  }
  const store = getCardStore(context)
  if (!store) {
    return
  }
  const list = getFavoriteCardIds(context)
  if (!list.includes(formId)) {
    try {
      list.push(formId)
      store.putSync(CARD_LIST_KEY, list)
      store.flushSync()
    } catch (_) {
    }
  }
}

export function removeFavoriteCardId(context: Context, formId: string): void {
  const store = getCardStore(context)
  if (!store) {
    return
  }
  const list = getFavoriteCardIds(context).filter((id) => id !== formId)
  try {
    store.putSync(CARD_LIST_KEY, list)
    store.flushSync()
  } catch (_) {
  }
}

export function createFavoriteCardBinding(snapshot: FavoriteCardSnapshot, formId?: string, dim?: number):
  formBindingData.FormBindingData {
  return formBindingData.createFormBindingData({
    formId: formId ?? '',
    dim: dim ?? 1,
    favorite_name: snapshot.favoriteName,
    favorite_uuid: snapshot.favoriteUuid,
    favorite_running: snapshot.favoriteRunning,
    favorite_updated_at: snapshot.updatedAt
  })
}
