import { InstanceInfo } from '../../class/InstanceInfo'
import { RuntimeInstanceState } from '../../types/runtime/RuntimeTypes'
import { updateTextNotification as updateLiveTextNotification } from '../../util/NoticeHelper'
import { updateFavorite } from '../form/CommunicationUtil'
import { RemoteManageService } from '../remote/RemoteManageService'
import { buildRuntimeNotifySignature } from './RuntimeStateReducer'

export interface FavoriteCardSignatureState {
  favoriteUuid: string
  favoriteName: string
  favoriteRunning: boolean
}

export class RuntimeNotificationService {
  private runtimeNotifySignature: string = ''
  private favoriteCardSignature: string = ''

  reset(): void {
    this.runtimeNotifySignature = ''
    this.favoriteCardSignature = ''
  }

  updateLiveText(instanceName: string, instanceInfo: InstanceInfo): void {
    updateLiveTextNotification(instanceName, instanceInfo)
  }

  notifyRuntimeChanged(instances: RuntimeInstanceState[], favoriteState: FavoriteCardSignatureState): void {
    const signature = buildRuntimeNotifySignature(instances)
    if (signature === this.runtimeNotifySignature) {
      this.notifyFavoriteCardChanged(favoriteState)
      return
    }
    this.runtimeNotifySignature = signature
    RemoteManageService.notifyHostSummaryDirty()
    this.notifyFavoriteCardChanged(favoriteState)
  }

  notifyFavoriteCardChanged(favoriteState: FavoriteCardSignatureState, force: boolean = false): void {
    const signature = this.buildFavoriteCardSignature(favoriteState)
    if (!force && signature === this.favoriteCardSignature) {
      return
    }
    this.favoriteCardSignature = signature
    updateFavorite()
  }

  private buildFavoriteCardSignature(favoriteState: FavoriteCardSignatureState): string {
    return [
      favoriteState.favoriteUuid,
      favoriteState.favoriteName,
      favoriteState.favoriteRunning ? '1' : '0'
    ].join(':')
  }
}
