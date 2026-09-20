import { fileIo } from '@kit.CoreFileKit'
import { Logger } from '../../shared/logging/Logger'

const LEASE_FILE_NAME = 'easytier-nearby-management.lease'
// Do not open a second descriptor while this process owns the lock: some record-lock
// implementations release process locks when any descriptor for that file closes.
const owners: Map<string, RuntimeHostLease> = new Map()

/** The lease file persists; only its OS lock is released on shutdown or process death. */
export class RuntimeHostLease {
  private readonly path: string
  private file: fileIo.File | undefined = undefined

  constructor(rootDir: string) {
    this.path = rootDir.length > 0 ? `${rootDir}/${LEASE_FILE_NAME}` : ''
  }

  tryAcquire(): boolean {
    if (this.file !== undefined) {
      return true
    }
    if (this.path.length === 0 || owners.has(this.path)) {
      return false
    }
    let file: fileIo.File | undefined = undefined
    try {
      file = fileIo.openSync(this.path, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE)
      file.tryLock(true)
    } catch (error) {
      if (file !== undefined) {
        try {
          fileIo.closeSync(file)
        } catch (closeError) {
          Logger.error(`host lease descriptor close failed: ${JSON.stringify(closeError)}`, 'RuntimeHostLease')
        }
      }
      Logger.debug(`host lease unavailable: ${JSON.stringify(error)}`, 'RuntimeHostLease')
      return false
    }
    this.file = file
    owners.set(this.path, this)
    return true
  }

  release(): void {
    if (this.file === undefined) {
      return
    }
    // Closing releases the lock. Keep ownership recorded if closing fails.
    fileIo.closeSync(this.file)
    this.file = undefined
    owners.delete(this.path)
  }

  static isAvailable(rootDir: string): boolean {
    const probe = new RuntimeHostLease(rootDir)
    if (!probe.tryAcquire()) {
      return false
    }
    probe.release()
    return true
  }
}
