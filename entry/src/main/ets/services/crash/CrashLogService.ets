import { AbilityConstant } from '@kit.AbilityKit'
import { buffer } from '@kit.ArkTS'
import { hiAppEvent } from '@kit.PerformanceAnalysisKit'
import { deviceInfo } from '@kit.BasicServicesKit'
import { fileIo } from '@kit.CoreFileKit'

const CRASH_LOG_FILE = 'easytier-crash.log'
const MAX_DIAGNOSTIC_LOG_CHARS = 8 * 1024 * 1024
const MAX_EXTERNAL_LOG_BYTES = 512 * 1024
const MAX_EXTERNAL_LOG_FILES = 8

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

function appendText(path: string, text: string): void {
  let previous = ''
  try {
    previous = fileIo.readTextSync(path)
  } catch (_) {
  }
  let combined = previous + text
  if (combined.length > MAX_DIAGNOSTIC_LOG_CHARS) {
    combined = '[older diagnostic records truncated]\n' +
      combined.substring(combined.length - MAX_DIAGNOSTIC_LOG_CHARS)
  }
  writeText(path, combined)
}

interface CrashLogDeviceInfo {
  marketName: string;
  productModel: string;
  osFullName: string;
  displayVersion: string;
  sdkApiVersion: number;
  abiList: string;
}

interface CrashEventParams {
  external_log?: string[]
}

interface ExternalLogEvidence {
  path: string
  sizeBytes: number
  capturedBytes: number
  truncated: boolean
  content: string
  error: string
}

interface LastExitDetailEvidence {
  exitSubReason: number
  exitMessage: string
  pid: number
  uid: number
  processName: string
  rssKb: number
  pssKb: number
  timestamp: number
  processState?: number
}

interface LastExitEvidenceRecord {
  recordType: string
  capturedAt: string
  reason: number
  message: string
  detail?: LastExitDetailEvidence
}

function readExternalLogEvidence(path: string): ExternalLogEvidence {
  let file: fileIo.File | null = null
  try {
    const sizeBytes = Number(fileIo.statSync(path).size)
    const requestedBytes = Math.min(Math.max(0, sizeBytes), MAX_EXTERNAL_LOG_BYTES)
    const raw = new ArrayBuffer(requestedBytes)
    file = fileIo.openSync(path, fileIo.OpenMode.READ_ONLY)
    const capturedBytes = requestedBytes > 0 ? fileIo.readSync(file.fd, raw, { length: requestedBytes }) : 0
    fileIo.closeSync(file)
    file = null
    return {
      path,
      sizeBytes,
      capturedBytes,
      truncated: capturedBytes < sizeBytes,
      content: capturedBytes > 0 ? buffer.from(raw, 0, capturedBytes).toString() : '',
      error: ''
    }
  } catch (error) {
    if (file) {
      try {
        fileIo.closeSync(file)
      } catch (_) {
      }
    }
    return {
      path,
      sizeBytes: 0,
      capturedBytes: 0,
      truncated: false,
      content: '',
      error: JSON.stringify(error)
    }
  }
}

function collectExternalLogs(appEventGroups: Array<hiAppEvent.AppEventGroup>): ExternalLogEvidence[] {
  const paths: string[] = []
  appEventGroups.forEach((group: hiAppEvent.AppEventGroup) => {
    group.appEventInfos.forEach((eventInfo: hiAppEvent.AppEventInfo) => {
      const eventParams = eventInfo.params as CrashEventParams
      eventParams.external_log?.forEach((path: string) => {
        if (path.length > 0 && paths.indexOf(path) < 0 && paths.length < MAX_EXTERNAL_LOG_FILES) {
          paths.push(path)
        }
      })
    })
  })
  return paths.map((path: string) => readExternalLogEvidence(path))
}

function buildCrashLog(domain: string, appEventGroups: Array<hiAppEvent.AppEventGroup>): string {
  return JSON.stringify({
    recordType: 'hi_app_event',
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
    appEventGroups,
    externalLogs: collectExternalLogs(appEventGroups)
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
        names: [
          hiAppEvent.event.APP_CRASH,
          hiAppEvent.event.APP_FREEZE,
          hiAppEvent.event.RESOURCE_OVERLIMIT
        ]
      }],
      onReceive: (domain: string, appEventGroups: Array<hiAppEvent.AppEventGroup>) => {
        if (appEventGroups.length === 0) {
          return
        }
        try {
          appendText(path, buildCrashLog(domain, appEventGroups))
        } catch (error) {
          appendText(path, JSON.stringify({
            recordType: 'hi_app_event_serialize_error',
            capturedAt: new Date().toISOString(),
            domain,
            error: `serialize crash event failed: ${JSON.stringify(error)}`
          }) + '\n')
        }
      }
    })
  }

  static recordLastExit(filesDir: string, launchParam: AbilityConstant.LaunchParam): void {
    if (filesDir.length === 0 || launchParam.lastExitReason === AbilityConstant.LastExitReason.UNKNOWN ||
      launchParam.lastExitReason === AbilityConstant.LastExitReason.NORMAL) {
      return
    }
    const detail = launchParam.lastExitDetailInfo
    let detailEvidence: LastExitDetailEvidence | undefined = undefined
    if (detail !== undefined) {
      detailEvidence = {
        exitSubReason: detail.exitSubReason,
        exitMessage: detail.exitMsg,
        pid: detail.pid,
        uid: detail.uid,
        processName: detail.processName,
        rssKb: detail.rss,
        pssKb: detail.pss,
        timestamp: detail.timestamp,
        processState: detail.processState
      }
    }
    const record: LastExitEvidenceRecord = {
      recordType: 'last_exit',
      capturedAt: new Date().toISOString(),
      reason: launchParam.lastExitReason,
      message: launchParam.lastExitMessage,
      detail: detailEvidence
    }
    appendText(crashLogPath(filesDir), JSON.stringify(record, undefined, 2) + '\n')
  }

  static recordRuntimeSignal(filesDir: string, signal: string, detail: string): void {
    if (filesDir.length === 0 || signal.length === 0) {
      return
    }
    appendText(crashLogPath(filesDir), JSON.stringify({
      recordType: 'runtime_signal',
      capturedAt: new Date().toISOString(),
      signal,
      detail
    }) + '\n')
  }

  static getLogPath(filesDir: string): string {
    return crashLogPath(filesDir)
  }
}
