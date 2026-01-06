export enum CardMethod {
  StartFavorite = "start_favorite",
  SendCardId = "send_card_id"
}

export function startFavorite(component: Object, formId: string) {
  postCardAction(component, {
    action: 'call',
    bundleName: 'top.frankhan.easytier',
    abilityName: 'EntryAbility',
    params: {
      method: CardMethod.StartFavorite,
      formId: formId
    }
  });
}

export function instancesList(component: Object) {
  postCardAction(component, {
    action: 'router',
    bundleName: 'top.frankhan.easytier',
    abilityName: 'EntryAbility',
    params: {
      target: "instance_list"
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