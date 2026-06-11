import { FavoriteCardActionMethod } from '../services/form/FavoriteCardActionService'

export enum CardMethod {
  StartFavorite = FavoriteCardActionMethod.StartFavorite,
  SendCardId = FavoriteCardActionMethod.SendCardId
}

export function startFavorite(component: Object) {
  postCardAction(component, {
    action: 'call',
    bundleName: 'top.frankhan.easytier',
    abilityName: 'EntryAbility',
    params: {
      method: CardMethod.StartFavorite
    }
  });
}

export function sendFormId(component: Object, formId: string) {
  postCardAction(component, {
    action: 'call',
    bundleName: 'top.frankhan.easytier',
    abilityName: 'EntryAbility',
    params: {
      method: CardMethod.SendCardId,
      formId: formId,
    },
  });
}

export function startApp(component: Object) {
  postCardAction(component, {
    action: 'router',
    bundleName: 'top.frankhan.easytier',
    abilityName: 'EntryAbility'
  });
}
