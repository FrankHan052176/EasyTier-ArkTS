import { FormExtensionAbility, formInfo, formProvider } from '@kit.FormKit';
import { Want } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import {
  addFavoriteCardId,
  createFavoriteCardBinding,
  readFavoriteCardSnapshot,
  removeFavoriteCardId
} from '../services/form/FavoriteCardState';

function parseFormDimension(raw: Object | undefined): number {
  if (typeof raw === 'number') {
    return raw
  }
  if (typeof raw === 'string') {
    const parsed = Number(raw)
    return Number.isNaN(parsed) ? 1 : parsed
  }
  return 1
}

export default class EntryFormAbility extends FormExtensionAbility {
  onAddForm(want: Want) {
    const formId = want.parameters![formInfo.FormParam.IDENTITY_KEY] as string;
    const dim = parseFormDimension(want.parameters![formInfo.FormParam.DIMENSION_KEY]);
    addFavoriteCardId(this.context, formId)
    return createFavoriteCardBinding(readFavoriteCardSnapshot(this.context), formId, dim);
  }

  onCastToNormalForm(formId: string) {
    // Called when the form provider is notified that a temporary form is successfully
    // converted to a normal form.
  }

  onUpdateForm(formId: string) {
    const formInfo = createFavoriteCardBinding(readFavoriteCardSnapshot(this.context), formId)
    formProvider.updateForm(formId, formInfo).catch((error: BusinessError) => {
      console.error(`onUpdateForm error: ${JSON.stringify(error)}`)
    })
  }

  onFormEvent(formId: string, message: string) {
    // Called when a specified message event defined by the form provider is triggered.
  }

  onRemoveForm(formId: string) {
    try {
      removeFavoriteCardId(this.context, formId)
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
