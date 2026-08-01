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

const MAX_SHARED_FILE_BYTES = 2 * 1024 * 1024

@LogLocate('SharedIntentImportService')
export class SharedIntentImportService {
  static async readUri(uri: string | undefined): Promise<ConfigTextImportResult> {
    Logger.info(`received shared URI length=${uri?.length ?? 0}`, 'SharedIntentImportService')
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
          Logger.info(`received shared record uri=${record.uri ? 'yes' : 'no'} content=${record.content ? 'yes' : 'no'}`,
            'SharedIntentImportService')
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

  private static async copySharedFileToCache(uri: string, cacheDir?: string): Promise<string | undefined> {
    if (!cacheDir || cacheDir.length === 0) {
      Logger.error('copy shared file failed: cacheDir is empty', 'SharedIntentImportService')
      return undefined
    }

    let file: fileIo.File | undefined = undefined
    let outFile: fileIo.File | undefined = undefined
    try {
      const sourceStat = fileIo.statSync(uri)
      if (sourceStat.size <= 0 || sourceStat.size > MAX_SHARED_FILE_BYTES) {
        Logger.error(`shared file rejected size=${sourceStat.size}`, 'SharedIntentImportService')
        return undefined
      }
      file = fileIo.openSync(uri, fileIo.OpenMode.READ_ONLY)
      const safeName = file.name.replace(/[\\/]/g, '_')
      const destPath = `${cacheDir}/${safeName.length > 0 ? safeName : 'shared-config'}`
      try {
        fileIo.unlinkSync(destPath)
      } catch (_) {
      }
      outFile = fileIo.openSync(destPath, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE)
      await fileIo.copyFile(file.fd, outFile.fd)
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
    Logger.debug(`read shared file uri length=${uri.length}`, 'SharedIntentImportService')
    const shareFilePath = await SharedIntentImportService.copySharedFileToCache(uri, cacheDir)
    if (!shareFilePath) {
      return false
    }

    try {
      Logger.info(`shared file copied nameLength=${shareFilePath.substring(shareFilePath.lastIndexOf('/') + 1).length}`,
        'SharedIntentImportService')
      let readTextOptions: ReadTextOptions = {
        offset: 0,
        length: 0,
        encoding: 'utf-8'
      };
      let stat = fileIo.statSync(shareFilePath);
      readTextOptions.length = stat.size;
      const content = await fileIo.readText(shareFilePath, readTextOptions)
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
