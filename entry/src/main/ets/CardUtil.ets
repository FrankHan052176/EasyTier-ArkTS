import { AppManager } from "./AppManager"
import { formBindingData, formProvider } from "@kit.FormKit"

export function updateFavoriteCard() {
  AppManager.preference.getCardList().forEach((formId) => {
    const data = formBindingData.createFormBindingData({
      favorite_name: AppManager.data.configUUIDNameMap.get(AppManager.data.favorite ?? "") ?? "",
      favorite_uuid: AppManager.data.favorite ?? "",
      favorite_running: AppManager.easytier.isFavoritesRunning()
    })
    formProvider.updateForm(formId, data)
  })
}