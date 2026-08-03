import { common } from '@kit.AbilityKit'
import { JSON } from '@kit.ArkTS'
import { fileIo } from '@kit.CoreFileKit'
import { hidebug } from '@kit.PerformanceAnalysisKit'
import { LogLocate, Logger } from '../../shared/logging/Logger'

const RUNTIME_STATS_FILE = 'easytier-runtime-stats.json'
const MEMORY_SAMPLE_INTERVAL_MS = 10000
const LIVE_REFRESH_INTERVAL_MS = 1000
const MAX_MEMORY_SAMPLES = 180
export const RUNTIME_STATS_STALE_AFTER_MS = 25000

interface RuntimeMemorySample {
  capturedAt: number
  memoryPssKb: string
  memoryRssKb: string
  vmHeapUsedKb: string
  vmHeapTotalKb: string
  systemAvailableKb: string
}

interface RuntimeStatsSnapshot {
  sessionId: string
  startedAt: number
  updatedAt: number
  runningMs: number
  memoryPssKb: string
  memoryRssKb?: string
  samples?: RuntimeMemorySample[]
}

async function collectRuntimeMemorySample(): Promise<RuntimeMemorySample> {
  let memoryPssKb = ''
  let memoryRssKb = ''
  let vmHeapUsedKb = ''
  let vmHeapTotalKb = ''
  let systemAvailableKb = ''
  try {
    const nativeMemory = await hidebug.getAppNativeMemInfoAsync()
    memoryPssKb = nativeMemory.pss.toString()
    memoryRssKb = nativeMemory.rss.toString()
  } catch (_) {
    try {
      const nativeMemory = hidebug.getAppNativeMemInfoWithCache()
      memoryPssKb = nativeMemory.pss.toString()
      memoryRssKb = nativeMemory.rss.toString()
    } catch (_) {
    }
  }
  try {
    const vmMemory = hidebug.getAppVMMemoryInfo()
    vmHeapUsedKb = vmMemory.heapUsed.toString()
    vmHeapTotalKb = vmMemory.totalHeap.toString()
  } catch (_) {
  }
  try {
    systemAvailableKb = hidebug.getSystemMemInfo().availableMem.toString()
  } catch (_) {
  }
  return {
    capturedAt: Date.now(),
    memoryPssKb,
    memoryRssKb,
    vmHeapUsedKb,
    vmHeapTotalKb,
    systemAvailableKb
  }
}

export function getRuntimeStatsFilePath(filesDir: string): string {
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
  private lastMemoryRssKb: string = ''
  private samples: RuntimeMemorySample[] = []

  start(filesDir: string): void {
    this.stop()
    this.filePath = getRuntimeStatsFilePath(filesDir)
    this.startedAt = Date.now()
    this.sessionNonce += 1
    this.sessionId = `${this.startedAt}-${this.sessionNonce}`
    this.lastMemoryPssKb = ''
    this.lastMemoryRssKb = ''
    this.samples = []
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
          memoryPssKb: this.lastMemoryPssKb,
          memoryRssKb: this.lastMemoryRssKb,
          samples: this.samples
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
    this.lastMemoryRssKb = ''
    this.samples = []
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
      const sample = await collectRuntimeMemorySample()
      if (this.sessionId !== currentSessionId || this.filePath !== currentFilePath || this.startedAt !== currentStartedAt) {
        return
      }
      this.lastMemoryPssKb = sample.memoryPssKb
      this.lastMemoryRssKb = sample.memoryRssKb
      this.samples.push(sample)
      while (this.samples.length > MAX_MEMORY_SAMPLES) {
        this.samples.shift()
      }
      const now = sample.capturedAt
      const snapshot: RuntimeStatsSnapshot = {
        sessionId: currentSessionId,
        startedAt: currentStartedAt,
        updatedAt: now,
        runningMs: now - currentStartedAt,
        memoryPssKb: sample.memoryPssKb,
        memoryRssKb: sample.memoryRssKb,
        samples: this.samples
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
  @Trace snapshotFreshnessText: string = '无运行采样'
  @Trace snapshotUpdatedAt: number = 0
  @Trace refreshTick: number = 0

  private filePath: string = ''
  private refreshTimer: number | undefined = undefined
  private ignoreSnapshotsBeforeMs: number = 0
  private liveRefreshRequested: boolean = false
  private uiForeground: boolean = true

  async init(context: common.UIAbilityContext): Promise<void> {
    this.filePath = getRuntimeStatsFilePath(context.filesDir)
    this.refreshFromDisk()
  }

  startLiveRefresh(resetForNewRun: boolean = false): void {
    this.liveRefreshRequested = true
    const alreadyRefreshing = this.refreshTimer !== undefined
    if (resetForNewRun && !alreadyRefreshing) {
      this.ignoreSnapshotsBeforeMs = Date.now()
      this.clearDisplay()
    }
    if (alreadyRefreshing || !this.uiForeground) {
      return
    }
    this.startRefreshTimer()
  }

  stopLiveRefresh(): void {
    this.liveRefreshRequested = false
    this.stopRefreshTimer()
  }

  setUiForeground(foreground: boolean): void {
    if (this.uiForeground === foreground) {
      return
    }
    this.uiForeground = foreground
    if (!foreground) {
      this.stopRefreshTimer()
      return
    }
    if (this.liveRefreshRequested) {
      this.startRefreshTimer()
    }
  }

  private startRefreshTimer(): void {
    if (this.refreshTimer !== undefined || !this.uiForeground) {
      return
    }
    this.refreshTimer = setInterval(() => {
      this.refreshFromDisk()
    }, LIVE_REFRESH_INTERVAL_MS)
    this.refreshFromDisk()
  }

  private stopRefreshTimer(): void {
    if (this.refreshTimer === undefined) {
      return
    }
    clearInterval(this.refreshTimer)
    this.refreshTimer = undefined
  }

  private clearDisplay(): void {
    this.runtimeDurationText = 'N/A'
    this.memoryUsageText = 'N/A'
    this.snapshotFreshnessText = '无运行采样'
    this.snapshotUpdatedAt = 0
  }

  private markRefreshed(): void {
    this.refreshTick = (this.refreshTick + 1) % 1000000
  }

  refreshFromDisk(): void {
    const snapshot = readRuntimeStatsSnapshot(this.filePath)
    if (!snapshot || snapshot.updatedAt < this.ignoreSnapshotsBeforeMs) {
      if (this.ignoreSnapshotsBeforeMs > 0) {
        this.clearDisplay()
      } else if (!snapshot) {
        this.clearDisplay()
      }
      this.markRefreshed()
      return
    }
    this.ignoreSnapshotsBeforeMs = 0
    const now = Date.now()
    this.snapshotUpdatedAt = snapshot.updatedAt
    const snapshotAgeMs = Math.max(0, now - snapshot.updatedAt)
    this.snapshotFreshnessText = snapshotAgeMs > RUNTIME_STATS_STALE_AFTER_MS ?
      `采样已中断 ${Math.trunc(snapshotAgeMs / 1000)} 秒` : '采样正常'
    const liveRunningMs = now - snapshot.updatedAt <= MEMORY_SAMPLE_INTERVAL_MS * 2 ?
      Math.max(snapshot.runningMs, now - snapshot.startedAt) :
      snapshot.runningMs
    this.runtimeDurationText = formatDuration(liveRunningMs)
    this.memoryUsageText = formatMemory(snapshot.memoryPssKb)
    this.markRefreshed()
  }

  isSnapshotStale(now: number = Date.now()): boolean {
    return this.snapshotUpdatedAt <= 0 || now - this.snapshotUpdatedAt > RUNTIME_STATS_STALE_AFTER_MS
  }
}
