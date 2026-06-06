export enum CardMethod {
  StartFavorite = "start_favorite",
  SendCardId = "send_card_id"
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
