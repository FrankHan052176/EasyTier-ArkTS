import { common } from '@kit.AbilityKit'
import { JSON } from '@kit.ArkTS'
import { fileIo } from '@kit.CoreFileKit'
import { hidebug } from '@kit.PerformanceAnalysisKit'
import { LogLocate, Logger } from '../../shared/logging/Logger'

const RUNTIME_STATS_FILE = 'easytier-runtime-stats.json'
const MEMORY_SAMPLE_INTERVAL_MS = 10000
const LIVE_REFRESH_INTERVAL_MS = 1000

interface RuntimeStatsSnapshot {
  sessionId: string
  startedAt: number
  updatedAt: number
  runningMs: number
  memoryPssKb: string
}

async function collectRuntimeMemoryPssKb(): Promise<string> {
  try {
    return (await hidebug.getAppNativeMemInfoAsync()).pss.toString()
  } catch (_) {
    try {
      return hidebug.getAppNativeMemInfoWithCache().pss.toString()
    } catch (_) {
      return ''
    }
  }
}

function runtimeStatsFilePath(filesDir: string): string {
  return `${filesDir}/${RUNTIME_STATS_FILE}`
}

function writeRuntimeStatsSnapshot(path: string, snapshot: RuntimeStatsSnapshot): void {
  const tempPath = `${path}.tmp`
  try {
    fileIo.unlinkSync(tempPath)
  } catch (_) {}
  let file: fileIo.File | null = null
  try {
    file = fileIo.openSync(tempPath, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE)
    fileIo.writeSync(file.fd, JSON.stringify(snapshot))
    fileIo.closeSync(file)
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
  private sessionId: string = ''
  private sessionNonce: number = 0
  private sampleInFlight: boolean = false
  private lastMemoryPssKb: string = ''

  start(filesDir: string): void {
    this.stop()
    this.filePath = runtimeStatsFilePath(filesDir)
    this.startedAt = Date.now()
    this.sessionNonce += 1
    this.sessionId = `${this.startedAt}-${this.sessionNonce}`
    this.lastMemoryPssKb = ''
    this.sampleAndPersist()
    this.timer = setInterval(() => {
      this.sampleAndPersist()
    }, MEMORY_SAMPLE_INTERVAL_MS)
  }

  stop(): void {
    if (this.filePath.length > 0 && this.startedAt > 0 && this.sessionId.length > 0) {
      try {
        const now = Date.now()
        writeRuntimeStatsSnapshot(this.filePath, {
          sessionId: this.sessionId,
          startedAt: this.startedAt,
          updatedAt: now,
          runningMs: now - this.startedAt,
          memoryPssKb: this.lastMemoryPssKb
        })
      } catch (_) {
      }
    }
    if (this.timer !== undefined) {
      clearInterval(this.timer)
      this.timer = undefined
    }
    this.filePath = ''
    this.startedAt = 0
    this.sessionId = ''
    this.sampleInFlight = false
    this.lastMemoryPssKb = ''
  }

  private async sampleAndPersist(): Promise<void> {
    if (this.sampleInFlight || this.filePath.length === 0 || this.startedAt <= 0 || this.sessionId.length === 0) {
      return
    }
    this.sampleInFlight = true
    const currentSessionId = this.sessionId
    const currentFilePath = this.filePath
    const currentStartedAt = this.startedAt
    try {
      const memoryPssKb = await collectRuntimeMemoryPssKb()
      if (this.sessionId !== currentSessionId || this.filePath !== currentFilePath || this.startedAt !== currentStartedAt) {
        return
      }
      this.lastMemoryPssKb = memoryPssKb
      const now = Date.now()
      const snapshot: RuntimeStatsSnapshot = {
        sessionId: currentSessionId,
        startedAt: currentStartedAt,
        updatedAt: now,
        runningMs: now - currentStartedAt,
        memoryPssKb
      }
      writeRuntimeStatsSnapshot(currentFilePath, snapshot)
    } catch (error) {
      if (this.sessionId !== currentSessionId || this.filePath !== currentFilePath || this.startedAt !== currentStartedAt) {
        return
      }
      Logger.error(`RuntimeStatsRecorder sample error: ${JSON.stringify(error)}`, 'RuntimeStatsRecorder')
    } finally {
      if (this.sessionId === currentSessionId && this.filePath === currentFilePath && this.startedAt === currentStartedAt) {
        this.sampleInFlight = false
      }
    }
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
    }, LIVE_REFRESH_INTERVAL_MS)
    this.refreshFromDisk()
  }

  stopLiveRefresh(): void {
    if (this.refreshTimer !== undefined) {
      clearInterval(this.refreshTimer)
      this.refreshTimer = undefined
    }
    this.runtimeDurationText = 'N/A'
    this.memoryUsageText = 'N/A'
  }

  refreshFromDisk(): void {
    const snapshot = readRuntimeStatsSnapshot(this.filePath)
    if (!snapshot) {
      this.runtimeDurationText = 'N/A'
      this.memoryUsageText = 'N/A'
      return
    }
    const now = Date.now()
    const liveRunningMs = now - snapshot.updatedAt <= MEMORY_SAMPLE_INTERVAL_MS * 2 ?
      Math.max(snapshot.runningMs, now - snapshot.startedAt) :
      snapshot.runningMs
    this.runtimeDurationText = formatDuration(liveRunningMs)
    this.memoryUsageText = formatMemory(snapshot.memoryPssKb)
  }
}
