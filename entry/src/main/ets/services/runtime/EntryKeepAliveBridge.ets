type EntryKeepAliveStartHandler = (name: string | undefined) => Promise<boolean>
type EntryKeepAliveStopHandler = () => Promise<void>

let startHandler: EntryKeepAliveStartHandler | undefined = undefined
let stopHandler: EntryKeepAliveStopHandler | undefined = undefined

export function registerEntryKeepAliveHandlers(start: EntryKeepAliveStartHandler,
  stop: EntryKeepAliveStopHandler): void {
  startHandler = start
  stopHandler = stop
}

export function unregisterEntryKeepAliveHandlers(): void {
  startHandler = undefined
  stopHandler = undefined
}

export async function requestEntryKeepAliveStart(name: string | undefined): Promise<boolean> {
  if (!startHandler) {
    return false
  }
  return await startHandler(name)
}

export async function requestEntryKeepAliveStop(): Promise<void> {
  if (stopHandler) {
    await stopHandler()
  }
}
