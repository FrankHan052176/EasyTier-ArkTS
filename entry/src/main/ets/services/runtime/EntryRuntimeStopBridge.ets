export interface EntryRuntimeStartRequest {
  configJson: string
  instanceId: string
  displayName: string
  oneShot: boolean
}

type EntryRuntimeStopHandler = (instanceIds: string[]) => Promise<boolean>
type EntryRuntimeStartHandler = (request: EntryRuntimeStartRequest) => Promise<boolean>
/**
 * 运行宿主归属同步：按 AppManager.uiState.ext_mode 释放/接管 UI 进程侧的
 * nearby host、命令 drain、内核 socket 与空闲 VPN 连接。返回 false 表示
 * 目标模式所需资源未就绪。
 */
type EntryRuntimeHostSyncHandler = () => Promise<boolean>

let stopHandler: EntryRuntimeStopHandler | undefined = undefined
let startHandler: EntryRuntimeStartHandler | undefined = undefined
let hostSyncHandler: EntryRuntimeHostSyncHandler | undefined = undefined

export function registerEntryRuntimeHandlers(start: EntryRuntimeStartHandler, stop: EntryRuntimeStopHandler,
  syncHost: EntryRuntimeHostSyncHandler): void {
  startHandler = start
  stopHandler = stop
  hostSyncHandler = syncHost
}

export function unregisterEntryRuntimeHandlers(): void {
  startHandler = undefined
  stopHandler = undefined
  hostSyncHandler = undefined
}

export async function requestEntryRuntimeStart(request: EntryRuntimeStartRequest): Promise<boolean> {
  if (!startHandler) {
    return false
  }
  return await startHandler(request)
}

export async function requestEntryRuntimeStop(instanceIds: string[]): Promise<boolean> {
  if (!stopHandler) {
    return false
  }
  return await stopHandler(instanceIds)
}

export async function requestEntryRuntimeHostSync(): Promise<boolean> {
  if (!hostSyncHandler) {
    return false
  }
  return await hostSyncHandler()
}
