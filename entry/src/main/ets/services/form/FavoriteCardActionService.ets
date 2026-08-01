import { Callee } from '@kit.AbilityKit'
import { JSON } from '@kit.ArkTS'
import { rpc } from '@kit.IPCKit'
import { AppManager } from '../../AppManager'
import { Logger, LogLocate } from '../../shared/logging/Logger'
import { EventHelper } from '../../util/EventHelper'
import { updateFavorite } from './CommunicationUtil'
import { FAVORITE_CARD_REFRESH_EVENT } from './FavoriteCardState'

export enum FavoriteCardActionMethod {
  StartFavorite = 'start_favorite',
  SendCardId = 'send_card_id'
}

@LogLocate('FavoriteCardActionService')
export class FavoriteCardActionService {
  private callee: Callee | undefined
  private listening: boolean = false

  private readonly favoriteCardRefreshCallback = () => {
    updateFavorite()
  }

  private readonly sendCardIdCallback = (indata: rpc.MessageSequence) => {
    try {
      const obj = JSON.parse(indata.readString()) as object
      const formId = obj['formId'] as string
      AppManager.preference.addCardId(formId)
      updateFavorite([formId])
    } catch (error) {
      Logger.error(`send_card_id parse error: ${JSON.stringify(error)}`, this)
    }
    return null
  }

  private readonly startFavoriteCallback = () => {
    if (AppManager.uiState.favorite) {
      if (AppManager.easytier.isFavoritesRunning()) {
        void AppManager.easytier.stopAndWait()
      } else {
        void AppManager.easytier.startAfterStop(AppManager.uiState.favorite, true)
      }
    }
    updateFavorite()
    return null
  }

  start(callee: Callee): void {
    if (this.listening) {
      return
    }
    this.callee = callee
    try {
      this.callee.on(FavoriteCardActionMethod.SendCardId, this.sendCardIdCallback)
      this.callee.on(FavoriteCardActionMethod.StartFavorite, this.startFavoriteCallback)
    } catch (error) {
      const message = `register card action failed: ${JSON.stringify(error)}`
      this.callee = undefined
      Logger.error(message, this)
      throw new Error(message)
    }
    EventHelper.emitterListener(FAVORITE_CARD_REFRESH_EVENT, this.favoriteCardRefreshCallback)
    this.listening = true
  }

  stop(): void {
    if (!this.listening) {
      return
    }
    EventHelper.emitterOff(FAVORITE_CARD_REFRESH_EVENT, this.favoriteCardRefreshCallback)
    try {
      this.callee?.off(FavoriteCardActionMethod.SendCardId)
      this.callee?.off(FavoriteCardActionMethod.StartFavorite)
    } catch (error) {
      Logger.error(`unregister card action failed: ${JSON.stringify(error)}`, this)
    }
    this.callee = undefined
    this.listening = false
  }

  refresh(): void {
    updateFavorite()
  }
}
