import { Want } from '@kit.AbilityKit'
import { url } from '@kit.ArkTS'
import { BusinessError } from '@kit.BasicServicesKit'
import { fileIo, ReadTextOptions } from '@kit.CoreFileKit'
import { systemShare } from '@kit.ShareKit'
import { AppManager } from '../../AppManager'
import { Logger, LogLocate } from '../../shared/logging/Logger'
import { ConfigTextImportResult, ConfigTextImportService } from './ConfigTextImportService'

function isHttpUrl(text: string | undefined): boolean {
  const lower = (text ?? '').toLowerCase()
  return lower.startsWith('http://') || lower.startsWith('https://')
}

@LogLocate('SharedIntentImportService')
export class SharedIntentImportService {
  static async readUri(uri: string | undefined): Promise<ConfigTextImportResult> {
    Logger.info(`get uri:${uri}`, 'SharedIntentImportService')
    const result = await ConfigTextImportService.importText(uri ?? "")
    if (!result.success) {
      Logger.error(`readUri import failed: ${result.message}`, 'SharedIntentImportService')
    }
    return result
  }

  static async readSharedData(want: Want, cacheDir?: string): Promise<void> {
    const uri = want.uri
    if (isHttpUrl(uri)) {
      await SharedIntentImportService.readUri(uri)
      return
    }

    let sharedDataError: Error | undefined = undefined
    let handled = false
    try {
      const data: systemShare.SharedData = await systemShare.getSharedData(want)
      const records = data?.getRecords()
      if (records) {
        for (const record of records) {
          Logger.info(JSON.stringify(record))
          if (record.uri && record.uri.length > 0) {
            handled = (await SharedIntentImportService.importSharedFile(record.uri, cacheDir)) || handled
          } else if (record.content && record.content.length > 0) {
            handled = (await SharedIntentImportService.importSharedContent(record.content)) || handled
          }
        }
      }
    } catch (error) {
      sharedDataError = error as Error
    }

    if (!handled && sharedDataError) {
      Logger.debug(`read shared data failed: ${JSON.stringify(sharedDataError)}`, 'SharedIntentImportService')
    }
  }

  private static copySharedFileToCache(uri: string, cacheDir?: string): string | undefined {
    if (!cacheDir || cacheDir.length === 0) {
      Logger.error('copy shared file failed: cacheDir is empty', 'SharedIntentImportService')
      return undefined
    }

    let file: fileIo.File | undefined = undefined
    let outFile: fileIo.File | undefined = undefined
    try {
      file = fileIo.openSync(uri, fileIo.OpenMode.READ_ONLY)
      const destPath = `${cacheDir}/${file.name}`
      outFile = fileIo.openSync(destPath, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE)
      fileIo.copyFileSync(file.fd, outFile.fd)
      return outFile.path
    } catch (error) {
      Logger.error(`copy shared file failed: ${JSON.stringify(error)}`, 'SharedIntentImportService')
      return undefined
    } finally {
      if (file) {
        try {
          fileIo.closeSync(file)
        } catch (error) {
          Logger.debug(`close shared file failed: ${JSON.stringify(error)}`, 'SharedIntentImportService')
        }
      }
      if (outFile) {
        try {
          fileIo.closeSync(outFile)
        } catch (error) {
          Logger.debug(`close copied shared file failed: ${JSON.stringify(error)}`, 'SharedIntentImportService')
        }
      }
    }
  }

  private static async importSharedFile(uri: string, cacheDir?: string): Promise<boolean> {
    Logger.debug(`read shared file uri: ${uri}`, 'SharedIntentImportService')
    const shareFilePath = SharedIntentImportService.copySharedFileToCache(uri, cacheDir)
    if (!shareFilePath) {
      return false
    }

    try {
      Logger.info(`copied file: ${shareFilePath}`, 'SharedIntentImportService')
      let readTextOptions: ReadTextOptions = {
        offset: 1,
        length: 0,
        encoding: 'utf-8'
      };
      let stat = fileIo.statSync(shareFilePath);
      readTextOptions.length = stat.size;
      const content = fileIo.readTextSync(shareFilePath, readTextOptions)
      const result = await ConfigTextImportService.importText(content)
      if (!result.success) {
        Logger.error(`import shared file failed: ${result.message}`, 'SharedIntentImportService')
      }
      return result.success
    } catch (error) {
      Logger.error(`read copied shared file failed: ${JSON.stringify(error)}`, 'SharedIntentImportService')
      return false
    }
  }

  private static async importSharedContent(content: string): Promise<boolean> {
    try {
      const urlObject = url.URL.parseURL(content)
      if (urlObject.hostname === 'appgallery.huawei.com') {
        const app = urlObject.params.get('id')
        Logger.debug(`get AppId: ${app}`, 'SharedIntentImportService')
        AppManager.web.getAppInfo(app!, (name, icon) => {
          AppManager.preference.setAppInfo(app!, name, icon)
        })
        return true
      }
    } catch (err) {
      const error = err as BusinessError
      Logger.debug(`shared content is not url, code: ${error.code}, message: ${error.message}`, 'SharedIntentImportService')
    }

    const result = await ConfigTextImportService.importText(content)
    if (!result.success) {
      Logger.error(`import shared content failed: ${result.message}`, 'SharedIntentImportService')
    }
    return result.success
  }
}
