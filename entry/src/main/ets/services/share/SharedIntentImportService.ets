import { Want } from '@kit.AbilityKit'
import { url } from '@kit.ArkTS'
import { BusinessError } from '@kit.BasicServicesKit'
import { fileIo as fs, fileUri } from '@kit.CoreFileKit'
import { systemShare } from '@kit.ShareKit'
import { AppManager } from '../../AppManager'
import { Logger, LogLocate } from '../../shared/logging/Logger'
import { unwrapUrl } from '../../util/ShareUtil'

@LogLocate('SharedIntentImportService')
export class SharedIntentImportService {
  static readUri(uri: string | undefined): void {
    Logger.info(`get uri:${uri}`, 'SharedIntentImportService')
    try {
      const urlObject = url.URL.parseURL(uri)
      unwrapUrl(urlObject)
    } catch (err) {
      const error = err as BusinessError
      Logger.error(`readUri error, code: ${error.code}, mesage: ${error.message}`, 'SharedIntentImportService')
    }
  }

  static async readSharedData(want: Want): Promise<void> {
    const uri = want.uri
    if (uri && uri.length > 0) {
      SharedIntentImportService.readUri(uri)
      return
    }

    systemShare.getSharedData(want)
      .then((data: systemShare.SharedData) => {
        data?.getRecords()?.forEach(async (record: systemShare.SharedRecord) => {
          if (record.uri && record.uri.length > 0) {
            SharedIntentImportService.importSharedFile(record)
          } else if (record.content && record.content.length > 0) {
            SharedIntentImportService.importSharedContent(record.content)
          }
        })
      })
  }

  private static importSharedFile(record: systemShare.SharedRecord): void {
    Logger.debug(`read shared file: ${JSON.stringify(record)}`, 'SharedIntentImportService')
    try {
      let cfg = ''
      try {
        cfg = fs.readTextSync(new fileUri.FileUri(record.uri).path)
      } catch (e) {
        Logger.error(`fs read error: ${JSON.stringify(e)}`, 'SharedIntentImportService')
      }
      if (cfg) {
        AppManager.data.importToml(cfg)
      }
    } catch (error) {
      Logger.debug(`read file error: ${JSON.stringify(error)}`, 'SharedIntentImportService')
    }
  }

  private static importSharedContent(content: string): void {
    const urlObject = url.URL.parseURL(content)
    const hostname = urlObject.hostname
    switch (hostname) {
      case 'appgallery.huawei.com': {
        const app = urlObject.params.get('id')
        Logger.debug(`get AppId: ${app}`, 'SharedIntentImportService')
        AppManager.web.getAppInfo(app!, (name, icon) => {
          AppManager.preference.setAppInfo(app!, name, icon)
        })
        break
      }
      case 'easytier.cn': {
        unwrapUrl(urlObject)
        break
      }
    }
  }
}
