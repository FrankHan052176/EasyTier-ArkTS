import { formBindingData, FormExtensionAbility, formInfo } from '@kit.FormKit';
import { Want } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';

export default class EntryFormAbility extends FormExtensionAbility {
  onAddForm(want: Want) {
    // Called to return a FormBindingData object.
    const formId = want.parameters![formInfo.FormParam.IDENTITY_KEY] as string;
    const dim = want.parameters![formInfo.FormParam.DIMENSION_KEY] as string;
    return formBindingData.createFormBindingData({
      formId,
      dim
    });
  }

  onCastToNormalForm(formId: string) {
    // Called when the form provider is notified that a temporary form is successfully
    // converted to a normal form.
  }

  onUpdateForm(formId: string) {
    // Called to notify the form provider to update a specified form.
  }

  onFormEvent(formId: string, message: string) {
    // Called when a specified message event defined by the form provider is triggered.
  }

  onRemoveForm(formId: string) {
    try {
      const store = preferences.getPreferencesSync(this.context, { name: 'EasyTierCardList' })
      let list = store.getSync('card_list', []) as string[]
      list = list.filter(id => id !== formId)
      store.putSync('card_list', list)
      store.flushSync()
    } catch (e) {
      // Form ability might not have Logger initialized or accessible easily, or just ignore.
      console.error(`onRemoveForm error: ${JSON.stringify(e)}`)
    }
  }

  onAcquireFormState(want: Want) {
    // Called to return a {@link FormState} object.
    return formInfo.FormState.READY;
  }
}