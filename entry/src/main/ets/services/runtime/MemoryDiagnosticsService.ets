import { BusinessError, deviceInfo } from '@kit.BasicServicesKit'
import { hidebug, jsLeakWatcher } from '@kit.PerformanceAnalysisKit'
import { Logger, LogLocate } from '../../shared/logging/Logger'

const MEMORY_PROBE_DELAY_MS = 1500

export interface MemoryDiagnosticsSnapshot {
  pssKb: string
  rssKb: string
  vssKb: string
  privateDirtyKb: string
  sharedCleanKb: string
  privateCleanKb: string
  nativeHeapSizeKb: string
  nativeHeapAllocatedKb: string
  nativeHeapFreeKb: string
  vmHeapUsedKb: string
  vmTotalHeapKb: string
  vmArrayKb: string
  vmObjectUsedKb: string
  gcCount: number
  gcBytesAllocated: number
}

function toKbText(value: bigint): string {
  return value.toString()
}

function bytesToKbText(value: bigint): string {
  return (value / 1024n).toString()
}

function gcValue(stats: hidebug.GcStats, key: string): number {
  return stats[key] ?? 0
}

function formatSnapshot(snapshot: MemoryDiagnosticsSnapshot): string {
  return `pss=${snapshot.pssKb}KB rss=${snapshot.rssKb}KB vss=${snapshot.vssKb}KB ` +
    `privateDirty=${snapshot.privateDirtyKb}KB nativeHeap=${snapshot.nativeHeapAllocatedKb}/${snapshot.nativeHeapSizeKb}KB ` +
    `nativeFree=${snapshot.nativeHeapFreeKb}KB vm=${snapshot.vmHeapUsedKb}/${snapshot.vmTotalHeapKb}KB ` +
    `vmObj=${snapshot.vmObjectUsedKb || 'N/A'}KB gc=${snapshot.gcCount} gcAlloc=${snapshot.gcBytesAllocated}`
}

@LogLocate('MemoryDiagnostics')
export class MemoryDiagnosticsService {
  private static leakWatcherEnabled: boolean = false
  private static pendingMarks: Set<string> = new Set()
  private static pendingMarkTimer: number = -1
  private static markInFlight: boolean = false
  private static heapDumpInFlight: boolean = false

  static async collectSnapshot(): Promise<MemoryDiagnosticsSnapshot | undefined> {
    try {
      const nativeInfo = deviceInfo.sdkApiVersion >= 20 ?
        await hidebug.getAppNativeMemInfoAsync() :
        hidebug.getAppNativeMemInfo()
      const vmInfo = hidebug.getAppVMMemoryInfo()
      const gcStats = hidebug.getVMRuntimeStats()
      return {
        pssKb: toKbText(nativeInfo.pss),
        rssKb: toKbText(nativeInfo.rss),
        vssKb: toKbText(nativeInfo.vss),
        privateDirtyKb: toKbText(nativeInfo.privateDirty),
        sharedCleanKb: toKbText(nativeInfo.sharedClean),
        privateCleanKb: toKbText(nativeInfo.privateClean),
        nativeHeapSizeKb: bytesToKbText(hidebug.getNativeHeapSize()),
        nativeHeapAllocatedKb: bytesToKbText(hidebug.getNativeHeapAllocatedSize()),
        nativeHeapFreeKb: bytesToKbText(hidebug.getNativeHeapFreeSize()),
        vmHeapUsedKb: toKbText(vmInfo.heapUsed),
        vmTotalHeapKb: toKbText(vmInfo.totalHeap),
        vmArrayKb: toKbText(vmInfo.allArraySize),
        vmObjectUsedKb: deviceInfo.sdkApiVersion >= 21 ? toKbText(hidebug.getAppVMObjectUsedSize()) : '',
        gcCount: gcValue(gcStats, 'ark.gc.gc-count'),
        gcBytesAllocated: gcValue(gcStats, 'ark.gc.gc-bytes-allocated')
      }
    } catch (error) {
      const err = error as BusinessError
      Logger.error(`collectSnapshot failed code=${err.code} message=${err.message}`, 'MemoryDiagnostics')
      return undefined
    }
  }

  static async mark(label: string): Promise<void> {
    if (MemoryDiagnosticsService.markInFlight) {
      return
    }
    MemoryDiagnosticsService.markInFlight = true
    const snapshot = await MemoryDiagnosticsService.collectSnapshot()
    try {
      if (!snapshot) {
        return
      }
      Logger.debug(`[MemoryProbe] ${label} ${formatSnapshot(snapshot)}`, 'MemoryDiagnostics')
    } finally {
      MemoryDiagnosticsService.markInFlight = false
    }
  }

  static markDelayed(label: string, delayMs: number = MEMORY_PROBE_DELAY_MS): void {
    MemoryDiagnosticsService.pendingMarks.add(label)
    if (MemoryDiagnosticsService.pendingMarkTimer >= 0) {
      return
    }
    MemoryDiagnosticsService.pendingMarkTimer = setTimeout(() => {
      MemoryDiagnosticsService.pendingMarkTimer = -1
      const labels = Array.from(MemoryDiagnosticsService.pendingMarks.values()).join(',')
      MemoryDiagnosticsService.pendingMarks.delete(label)
      MemoryDiagnosticsService.pendingMarks.clear()
      void MemoryDiagnosticsService.mark(labels)
    }, delayMs)
  }

  static watchObject(obj: object, label: string): void {
    try {
      if (!MemoryDiagnosticsService.leakWatcherEnabled) {
        jsLeakWatcher.enable(true)
        MemoryDiagnosticsService.leakWatcherEnabled = true
      }
      jsLeakWatcher.watch(obj, label)
    } catch (error) {
      const err = error as BusinessError
      Logger.error(`watchObject failed label=${label} code=${err.code} message=${err.message}`, 'MemoryDiagnostics')
    }
  }

  static checkLeaks(label: string, filesDir?: string): void {
    try {
      const leakList = jsLeakWatcher.check()
      if (leakList.length > 0) {
        Logger.error(`[JsLeakWatcher] ${label} ${leakList}`, 'MemoryDiagnostics')
      } else {
        Logger.debug(`[JsLeakWatcher] ${label} empty`, 'MemoryDiagnostics')
      }
      if (filesDir && leakList.length > 0) {
        const files = jsLeakWatcher.dump(filesDir)
        Logger.error(`[JsLeakWatcher] ${label} dump=${files.join(',')}`, 'MemoryDiagnostics')
      }
    } catch (error) {
      const err = error as BusinessError
      Logger.error(`checkLeaks failed label=${label} code=${err.code} message=${err.message}`, 'MemoryDiagnostics')
    }
  }

  static checkLeaksDelayed(label: string, delayMs: number = MEMORY_PROBE_DELAY_MS, filesDir?: string): void {
    setTimeout(() => {
      MemoryDiagnosticsService.checkLeaks(label, filesDir)
    }, delayMs)
  }

  static enableSystemLeakWatcher(enabled: boolean): void {
    if (!enabled) {
      MemoryDiagnosticsService.pendingMarks.clear()
      if (MemoryDiagnosticsService.pendingMarkTimer >= 0) {
        clearTimeout(MemoryDiagnosticsService.pendingMarkTimer)
        MemoryDiagnosticsService.pendingMarkTimer = -1
      }
      try {
        if (MemoryDiagnosticsService.leakWatcherEnabled) {
          jsLeakWatcher.enable(false)
          MemoryDiagnosticsService.leakWatcherEnabled = false
        }
      } catch (_) {
      }
    }
    if (deviceInfo.sdkApiVersion < 20) {
      return
    }
    try {
      jsLeakWatcher.enableLeakWatcher(enabled, [], (files: Array<string>) => {
        Logger.error(`[JsLeakWatcher] auto leakList=${files[0] ?? ''} rawHeap=${files[1] ?? ''}`, 'MemoryDiagnostics')
      })
    } catch (error) {
      const err = error as BusinessError
      Logger.error(`enableSystemLeakWatcher failed code=${err.code} message=${err.message}`, 'MemoryDiagnostics')
    }
  }
}
