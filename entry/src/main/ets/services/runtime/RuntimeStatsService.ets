import { common } from '@kit.AbilityKit'
import { JSON, taskpool } from '@kit.ArkTS'
import { fileIo } from '@kit.CoreFileKit'
import hidebug from '@ohos.hidebug'
import { LogLocate, Logger } from '../../shared/logging/Logger'

const RUNTIME_STATS_FILE = 'easytier-runtime-stats.json'
const SAMPLE_INTERVAL_MS = 100

interface RuntimeStatsSnapshot {
  startedAt: number
  updatedAt: number
  runningMs: number
  memoryPssKb: string
}

@Concurrent
async function collectRuntimeMemoryPssKb(): Promise<string> {
  try {
    return hidebug.getAppNativeMemInfo().pss.toString()
  } catch (_) {
    return ''
  }
}

function runtimeStatsFilePath(filesDir: string): string {
  return `${filesDir}/${RUNTIME_STATS_FILE}`
}

function writeRuntimeStatsSnapshot(path: string, snapshot: RuntimeStatsSnapshot): void {
  try {
    fileIo.unlinkSync(path)
  } catch (_) {}
  let file: fileIo.File | null = null
  try {
    file = fileIo.openSync(path, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE)
    fileIo.writeSync(file.fd, JSON.stringify(snapshot))
    fileIo.closeSync(file)
  } catch (error) {
    if (file) {
      try {
        fileIo.closeSync(file)
      } catch (_) {}
    }
    throw new Error(`writeRuntimeStatsSnapshot failed: ${JSON.stringify(error)}`)
  }
}

function readRuntimeStatsSnapshot(path: string): RuntimeStatsSnapshot | undefined {
  try {
    const content = fileIo.readTextSync(path)
    if (content.length === 0) {
      return undefined
    }
    return JSON.parse(content) as RuntimeStatsSnapshot
  } catch (_) {
    return undefined
  }
}

function formatDuration(ms: number): string {
  const totalSeconds = Math.max(0, Math.trunc(ms / 1000))
  const hours = Math.trunc(totalSeconds / 3600)
  const minutes = Math.trunc((totalSeconds % 3600) / 60)
  const seconds = totalSeconds % 60
  return `${String(hours).padStart(2, '0')}:${String(minutes).padStart(2, '0')}:${String(seconds).padStart(2, '0')}`
}

function formatMemory(memoryPssKb: string): string {
  const valueKb = Number.parseInt(memoryPssKb, 10)
  if (!Number.isFinite(valueKb) || valueKb <= 0) {
    return 'N/A'
  }
  const valueMb = valueKb / 1024
  return `${valueMb.toFixed(1)} MB`
}

class RuntimeStatsRecorder {
  private timer: number | undefined = undefined
  private startedAt: number = 0
  private filePath: string = ''
  private sampling: boolean = false

  start(filesDir: string): void {
    this.stop()
    this.filePath = runtimeStatsFilePath(filesDir)
    this.startedAt = Date.now()
    this.sampleAndPersist()
    this.timer = setInterval(() => {
      this.sampleAndPersist()
    }, SAMPLE_INTERVAL_MS)
  }

  stop(): void {
    if (this.timer !== undefined) {
      clearInterval(this.timer)
      this.timer = undefined
    }
    this.filePath = ''
    this.startedAt = 0
    this.sampling = false
  }

  private sampleAndPersist(): void {
    if (this.sampling || this.filePath.length === 0 || this.startedAt <= 0) {
      return
    }
    this.sampling = true
    taskpool.execute(collectRuntimeMemoryPssKb).then((result) => {
      const memoryPssKb = String(result ?? '')
      const now = Date.now()
      const snapshot: RuntimeStatsSnapshot = {
        startedAt: this.startedAt,
        updatedAt: now,
        runningMs: now - this.startedAt,
        memoryPssKb
      }
      writeRuntimeStatsSnapshot(this.filePath, snapshot)
    }).catch((error: Error) => {
      Logger.error(`RuntimeStatsRecorder sample error: ${JSON.stringify(error)}`, 'RuntimeStatsRecorder')
    }).finally(() => {
      this.sampling = false
    })
  }
}

const runtimeStatsRecorder = new RuntimeStatsRecorder()

export function startRuntimeStatsRecording(filesDir: string): void {
  runtimeStatsRecorder.start(filesDir)
}

export function stopRuntimeStatsRecording(): void {
  runtimeStatsRecorder.stop()
}

@LogLocate('RuntimeStatsService')
@ObservedV2
export class RuntimeStatsService {
  @Trace runtimeDurationText: string = 'N/A'
  @Trace memoryUsageText: string = 'N/A'

  private filePath: string = ''
  private refreshTimer: number | undefined = undefined

  async init(context: common.UIAbilityContext): Promise<void> {
    this.filePath = runtimeStatsFilePath(context.filesDir)
    this.refreshFromDisk()
  }

  startLiveRefresh(): void {
    if (this.refreshTimer !== undefined) {
      return
    }
    this.refreshTimer = setInterval(() => {
      this.refreshFromDisk()
    }, 100)
    this.refreshFromDisk()
  }

  stopLiveRefresh(): void {
    if (this.refreshTimer !== undefined) {
      clearInterval(this.refreshTimer)
      this.refreshTimer = undefined
    }
  }

  refreshFromDisk(): void {
    const snapshot = readRuntimeStatsSnapshot(this.filePath)
    if (!snapshot) {
      return
    }
    this.runtimeDurationText = formatDuration(snapshot.runningMs)
    this.memoryUsageText = formatMemory(snapshot.memoryPssKb)
  }
}
