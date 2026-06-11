import easytier from 'easytier-ohrs'
import { common } from '@kit.AbilityKit'
import { uniformTypeDescriptor } from '@kit.ArkData'
import { fileIo, fileUri } from '@kit.CoreFileKit'
import { systemShare } from '@kit.ShareKit'
import { AppManager } from '../../AppManager'
import { Logger, LogLocate } from '../../shared/logging/Logger'
import { sendToast } from '../../ToastUtil'
import { CrashLogService } from '../crash/CrashLogService'
import { LogFileEntry } from '../../types/logging/LogFileTypes'

const SHARE_EXCLUDED_ABILITIES: systemShare.ShareAbilityType[] = [
  systemShare.ShareAbilityType.PRINT,
  systemShare.ShareAbilityType.SAVE_TO_SUPERHUB
]

function sanitizeFileName(fileName: string): string {
  return fileName
    .split('')
    .map((ch: string) => {
      const code = ch.charCodeAt(0)
      const isDigit = code >= 48 && code <= 57
      const isUpper = code >= 65 && code <= 90
      const isLower = code >= 97 && code <= 122
      return isDigit || isUpper || isLower || ch === '-' || ch === '_' || ch === '.' ? ch : '-'
    })
    .join('')
}

function closeFileQuietly(file: fileIo.File | null): void {
  if (!file) {
    return
  }
  try {
    fileIo.closeSync(file)
  } catch (_) {
  }
}

function unlinkQuietly(path: string): void {
  try {
    fileIo.unlinkSync(path)
  } catch (_) {
  }
}

function getContext(): common.UIAbilityContext {
  return AppManager.content.context! as common.UIAbilityContext
}

function showFileShare(context: common.UIAbilityContext, filePath: string, title: string, logLabel: string): void {
  const shareData: systemShare.SharedData = new systemShare.SharedData({
    utd: uniformTypeDescriptor.UniformDataType.FILE,
    uri: fileUri.getUriFromPath(filePath),
    title
  })
  const controller: systemShare.ShareController = new systemShare.ShareController(shareData)
  controller.show(context, {
    selectionMode: systemShare.SelectionMode.SINGLE,
    previewMode: systemShare.SharePreviewMode.DEFAULT,
    excludedAbilities: SHARE_EXCLUDED_ABILITIES
  }).catch(() => {
    Logger.error(`${logLabel}::An unexpected error occurred.`, 'LogCenterService')
  })
}

@LogLocate('LogCenterService')
export class LogCenterService {
  static listLogFiles(): LogFileEntry[] {
    try {
      return easytier.listLogFiles() as LogFileEntry[]
    } catch (error) {
      Logger.error(`listLogFiles failed: ${JSON.stringify(error)}`, 'LogCenterService')
      return []
    }
  }

  static readLogFileLines(fileName: string): string[] {
    try {
      const content = easytier.readLogFile(fileName)
      if (!content) {
        return []
      }
      return content
        .split('\n')
        .map((line: string) => line.endsWith('\r') ? line.substring(0, line.length - 1) : line)
        .filter((line: string) => line.length > 0)
    } catch (error) {
      Logger.error(`readLogFileLines failed file=${fileName} err=${JSON.stringify(error)}`, 'LogCenterService')
      return []
    }
  }

  static writeAndShareLogs(fallbackLogText: string): void {
    const filePath = `${getContext().filesDir}/log.txt`
    let file: fileIo.File | null = null
    unlinkQuietly(filePath)
    try {
      if (!easytier.exportLogArchive(filePath)) {
        file = fileIo.openSync(filePath, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE)
        fileIo.writeSync(file.fd, fallbackLogText)
        fileIo.closeSync(file)
        file = null
      }

      showFileShare(getContext(), filePath, '分享日志', 'systemShareConfig')
    } catch (err) {
      closeFileQuietly(file)
      Logger.error(`日志文件写入失败. Code: ${err.code}, message: ${err.message}`, 'LogCenterService')
    }
  }

  static writeAndShareLogFile(fileName: string): void {
    const context = getContext()
    const safeName = sanitizeFileName(fileName)
    const targetPath = `${context.filesDir}/share-${safeName.length > 0 ? safeName : 'easytier.log'}`
    unlinkQuietly(targetPath)

    try {
      if (!easytier.exportLogFile(fileName, targetPath)) {
        sendToast('日志导出失败', $r('sys.symbol.exclamationmark_circle'), 1)
        return
      }

      showFileShare(context, targetPath, '分享日志', 'systemShareLogFile')
    } catch (err) {
      Logger.error(`日志分享失败. Code: ${err.code}, message: ${err.message}`, 'LogCenterService')
    }
  }

  static writeAndShareCrashLog(): void {
    const context = getContext()
    const filePath = CrashLogService.getLogPath(context.filesDir)
    try {
      if (Number(fileIo.statSync(filePath).size) <= 0) {
        sendToast('暂无崩溃日志', $r('sys.symbol.doc'), 1)
        return
      }
    } catch (_) {
      sendToast('暂无崩溃日志', $r('sys.symbol.doc'), 1)
      return
    }

    try {
      showFileShare(context, filePath, '分享崩溃日志', 'systemShareCrashLog')
    } catch (err) {
      Logger.error(`崩溃日志分享失败. Code: ${err.code}, message: ${err.message}`, 'LogCenterService')
    }
  }
}
