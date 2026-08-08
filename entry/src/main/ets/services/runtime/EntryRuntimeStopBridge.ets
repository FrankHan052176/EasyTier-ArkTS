export interface EntryRuntimeStartRequest {
  configJson: string
  instanceId: string
  displayName: string
  oneShot: boolean
}

type EntryRuntimeStopHandler = (instanceIds: string[]) => Promise<boolean>
type EntryRuntimeStartHandler = (request: EntryRuntimeStartRequest) => Promise<boolean>

let stopHandler: EntryRuntimeStopHandler | undefined = undefined
let startHandler: EntryRuntimeStartHandler | undefined = undefined

export function registerEntryRuntimeHandlers(start: EntryRuntimeStartHandler, stop: EntryRuntimeStopHandler): void {
  startHandler = start
  stopHandler = stop
}

export function unregisterEntryRuntimeHandlers(): void {
  startHandler = undefined
  stopHandler = undefined
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
