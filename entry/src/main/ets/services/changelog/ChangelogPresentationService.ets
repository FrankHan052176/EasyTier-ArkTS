import { bundleManager } from '@kit.AbilityKit'
import { AppManager } from '../../AppManager'
import { Logger } from '../../shared/logging/Logger'

const LAST_PRESENTED_VERSION_KEY = 'changelog_last_presented_app_version'

class ChangelogPresentationServiceClass {
  private currentVersionToken(): string | undefined {
    try {
      const bundleInfo = bundleManager.getBundleInfoForSelfSync(bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT)
      return `${bundleInfo.versionCode}:${bundleInfo.versionName}`
    } catch (error) {
      Logger.error(`read current app version failed: ${JSON.stringify(error)}`, 'ChangelogPresentationService')
      return undefined
    }
  }

  /**
   * 当前安装版本尚未展示过更新日志时返回 true，并在返回前写入版本标记。
   * 使用 versionCode + versionName，既覆盖正式升级，也覆盖调试包版本文本变化。
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
