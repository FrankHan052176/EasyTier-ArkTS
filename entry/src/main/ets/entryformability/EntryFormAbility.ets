import { formBindingData, FormExtensionAbility, formInfo } from '@kit.FormKit';
import { Want } from '@kit.AbilityKit';
import { Logger } from '../util/Logger';

export default class EntryFormAbility extends FormExtensionAbility {
  onAddForm(want: Want) {
    if (want.parameters) {
      let formId = want.parameters[formInfo.FormParam.IDENTITY_KEY] as string;
      let formType = want.parameters[formInfo.FormParam.NAME_KEY] as string;
      let dimension = want.parameters[formInfo.FormParam.DIMENSION_KEY] as string;
      let temp = want.parameters[formInfo.FormParam.TEMPORARY_KEY] as string;
      Logger.debug("form:"+formId+formType+dimension+temp)
    }
    const formData = '';
    return formBindingData.createFormBindingData(formData);
  }

  onCastToNormalForm(formId: string) {
    Logger.debug("Normal:"+formId)
  }

  onUpdateForm(formId: string) {

  }

  onFormEvent(formId: string, message: string) {

  }

  onRemoveForm(formId: string) {

  }

  onAcquireFormState(want: Want) {
    return formInfo.FormState.READY;
  }
}