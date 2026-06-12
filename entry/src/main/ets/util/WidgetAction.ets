import { FavoriteCardActionMethod } from '../services/form/FavoriteCardActionService'
import { APP_BUNDLE_NAME, ENTRY_ABILITY_NAME } from '../services/runtime/AbilityRuntimePolicy'

export enum CardMethod {
  StartFavorite = FavoriteCardActionMethod.StartFavorite,
  SendCardId = FavoriteCardActionMethod.SendCardId
}

export function startFavorite(component: Object) {
  postCardAction(component, {
    action: 'call',
    bundleName: APP_BUNDLE_NAME,
    abilityName: ENTRY_ABILITY_NAME,
    params: {
      method: CardMethod.StartFavorite
    }
  });
}

export function sendFormId(component: Object, formId: string) {
  postCardAction(component, {
    action: 'call',
    bundleName: APP_BUNDLE_NAME,
    abilityName: ENTRY_ABILITY_NAME,
    params: {
      method: CardMethod.SendCardId,
      formId: formId,
    },
  });
}

export function startApp(component: Object) {
  postCardAction(component, {
    action: 'router',
    bundleName: APP_BUNDLE_NAME,
    abilityName: ENTRY_ABILITY_NAME
  });
}
