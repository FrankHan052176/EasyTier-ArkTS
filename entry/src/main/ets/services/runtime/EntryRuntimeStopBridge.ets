type EntryRuntimeStopHandler = () => Promise<void>
type EntryRuntimeStartHandler = (cfg: string, uuid: string | undefined, name: string | undefined,
  shouldProtect: boolean) => Promise<boolean>

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

export async function requestEntryRuntimeStart(cfg: string, uuid: string | undefined, name: string | undefined,
  shouldProtect: boolean): Promise<boolean> {
  if (!startHandler) {
    return false
  }
  return await startHandler(cfg, uuid, name, shouldProtect)
}

export async function requestEntryRuntimeStop(): Promise<void> {
  if (stopHandler) {
    await stopHandler()
  }
}
