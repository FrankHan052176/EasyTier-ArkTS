import { hiAppEvent } from '@kit.PerformanceAnalysisKit'
import { deviceInfo } from '@kit.BasicServicesKit'
import { fileIo } from '@kit.CoreFileKit'

const CRASH_LOG_FILE = 'easytier-crash.log'

function crashLogPath(filesDir: string): string {
  return `${filesDir}/${CRASH_LOG_FILE}`
}

function writeText(path: string, text: string): void {
  const tempPath = `${path}.tmp`
  let file: fileIo.File | null = null
  try {
    try {
      fileIo.unlinkSync(tempPath)
    } catch (_) {}
    file = fileIo.openSync(tempPath, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE)
    fileIo.writeSync(file.fd, text)
    fileIo.closeSync(file)
    file = null
    try {
      fileIo.unlinkSync(path)
    } catch (_) {}
    fileIo.renameSync(tempPath, path)
  } catch (error) {
    if (file) {
      try {
        fileIo.closeSync(file)
      } catch (_) {}
    }
    try {
      fileIo.unlinkSync(tempPath)
    } catch (_) {}
    console.error(`CrashLogService write failed: ${JSON.stringify(error)}`)
  }
}

interface CrashLogDeviceInfo {
  marketName: string;
  productModel: string;
  osFullName: string;
  displayVersion: string;
  sdkApiVersion: number;
  abiList: string;
}

function buildCrashLog(domain: string, appEventGroups: Array<hiAppEvent.AppEventGroup>): string {
  return JSON.stringify({
    capturedAt: new Date().toISOString(),
    domain,
    device: ({
      marketName: deviceInfo.marketName,
      productModel: deviceInfo.productModel,
      osFullName: deviceInfo.osFullName,
      displayVersion: deviceInfo.displayVersion,
      sdkApiVersion: deviceInfo.sdkApiVersion,
      abiList: deviceInfo.abiList
    } as CrashLogDeviceInfo),
    appEventGroups
  }, undefined, 2) + '\n'
}

export class CrashLogService {
  private static initialized: boolean = false

  static init(filesDir: string): void {
    if (CrashLogService.initialized || filesDir.length === 0) {
      return
    }
    CrashLogService.initialized = true
    const path = crashLogPath(filesDir)
    hiAppEvent.addWatcher({
      name: 'EasyTierCrashLog',
      appEventFilters: [{
        domain: hiAppEvent.domain.OS,
        names: [hiAppEvent.event.APP_CRASH]
      }],
      onReceive: (domain: string, appEventGroups: Array<hiAppEvent.AppEventGroup>) => {
        if (appEventGroups.length === 0) {
          return
        }
        try {
          writeText(path, buildCrashLog(domain, appEventGroups))
        } catch (error) {
          writeText(path, JSON.stringify({
            capturedAt: new Date().toISOString(),
            domain,
            error: `serialize crash event failed: ${JSON.stringify(error)}`
          }) + '\n')
        }
      }
    })
  }

  static getLogPath(filesDir: string): string {
    return crashLogPath(filesDir)
  }
}
