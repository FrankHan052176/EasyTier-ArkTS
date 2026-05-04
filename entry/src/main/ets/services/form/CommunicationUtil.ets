import { AppManager } from "../../AppManager"
import { formBindingData, formProvider } from "@kit.FormKit"
import { Logger } from "../../shared/logging/Logger"
import { BusinessError } from "@kit.BasicServicesKit";

export function updateFavorite() {
  let voidForm: string[] = []
  AppManager.preference.getCardList().forEach((formId) => {
    let formInfo = formBindingData.createFormBindingData({
      favorite_name: AppManager.uiState.favorite ? (AppManager.easytier.getConfigName(AppManager.uiState.favorite) ?? "") : "",
      favorite_uuid: AppManager.uiState.favorite ?? "",
      favorite_running: AppManager.easytier.isFavoritesRunning()
    });
    formProvider.updateForm(formId, formInfo).catch((e: BusinessError) => {
      if (e.code == 16501001) {
        voidForm.push(formId)
      }
    })
  })

}
