import { bundleManager } from '@kit.AbilityKit'
import { AppManager } from '../../AppManager'
import { CHANGELOG_REVISION } from '../../pages/hmrouter/ChangelogData'
import { Logger } from '../../shared/logging/Logger'
import { APP_CHANNEL } from '../../util/info/BuildTime'

const LAST_PRESENTED_VERSION_KEY = 'changelog_last_presented_app_version'

class ChangelogPresentationServiceClass {
  private currentVersionToken(): string | undefined {
    try {
      const bundleInfo = bundleManager.getBundleInfoForSelfSync(bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT)
      return `${bundleInfo.versionCode}:${bundleInfo.versionName}:${APP_CHANNEL}:${CHANGELOG_REVISION}`
    } catch (error) {
      Logger.error(`read current app version failed: ${JSON.stringify(error)}`, 'ChangelogPresentationService')
      return undefined
    }
  }

  /**
   * 当前安装版本尚未展示过更新日志时返回 true，并在返回前写入版本标记。
   * 使用应用版本与更新记录修订号，既覆盖正式升级，也覆盖固定版本号的开发包内容变化。
   */
  consumeCurrentVersion(): boolean {
    const store = AppManager.preference.preferences
    if (!store) {
      return false
    }
    const currentVersion = this.currentVersionToken()
    if (!currentVersion) {
      return false
    }
    try {
      const presentedVersion = store.getSync(LAST_PRESENTED_VERSION_KEY, '').toString()
      if (presentedVersion === currentVersion) {
        return false
      }
      store.putSync(LAST_PRESENTED_VERSION_KEY, currentVersion)
      store.flushSync()
      Logger.info(`present changelog for app version ${currentVersion}`, 'ChangelogPresentationService')
      return true
    } catch (error) {
      Logger.error(`persist changelog version failed: ${JSON.stringify(error)}`, 'ChangelogPresentationService')
      return false
    }
  }
}

export const ChangelogPresentationService = new ChangelogPresentationServiceClass()
