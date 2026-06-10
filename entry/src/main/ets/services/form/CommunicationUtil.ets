import { AppManager } from "../../AppManager"
import { formProvider } from "@kit.FormKit"
import { Logger } from "../../shared/logging/Logger"
import { BusinessError } from "@kit.BasicServicesKit";
import {
  createFavoriteCardBinding,
  FavoriteCardSnapshot,
  writeFavoriteCardSnapshot
} from './FavoriteCardState'

function buildFavoriteSnapshot(): FavoriteCardSnapshot {
  const favoriteUuid = AppManager.uiState.favorite ?? ''
  return {
    favoriteUuid,
    favoriteName: favoriteUuid.length > 0 ? AppManager.easytier.getConfigName(favoriteUuid) ?? favoriteUuid : '',
    favoriteRunning: AppManager.easytier.isFavoritesRunning(),
    updatedAt: Date.now()
  }
}

export function updateFavorite(targetFormIds?: string[]) {
  const context = AppManager.content.context
  if (!context) {
    return
  }
  const snapshot = buildFavoriteSnapshot()
  writeFavoriteCardSnapshot(context, snapshot)
  let voidForm: string[] = []
  const formIds = targetFormIds ?? AppManager.preference.getCardList()
  formIds.forEach((formId) => {
    let formInfo = createFavoriteCardBinding(snapshot, formId)
    formProvider.updateForm(formId, formInfo).catch((e: BusinessError) => {
      if (e.code == 16501001) {
        voidForm.push(formId)
        AppManager.preference.cleanCardList(voidForm)
      } else {
        Logger.error(`update favorite form failed, formId=${formId}, code=${e.code}, message=${e.message}`, "CommunicationUtil")
      }
    })
  })
}
