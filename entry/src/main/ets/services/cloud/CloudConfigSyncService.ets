import { common } from '@kit.AbilityKit'
import { JSON } from '@kit.ArkTS'
import { cloudSync, fileIo, fileUri } from '@kit.CoreFileKit'
import easytier from 'easytier-ohrs'
import { AppManager } from '../../AppManager'
import { CLOUD_CONFIG_CHANGED_EVENT } from '../../ConfigSyncUtil'
import { EventHelper } from '../../util/EventHelper'
import { Logger, LogLocate } from '../../shared/logging/Logger'

const CLOUD_SYNC_DIR = 'easytier-sync'
const CLOUD_DB_FILE = 'easytier-config-store.db'
const META_FILE = 'sync-meta.json'

interface SyncMeta {
  version: number
  updatedAt: string
}

interface SnapshotApi extends ESObject {
  exportConfigStoreSnapshot?: (targetPath: string) => boolean
  importConfigStoreSnapshot?: (sourcePath: string) => boolean
}

interface StoredConfigMetaLite {
  configId: string
  displayName: string
  updatedAt?: string
}

@LogLocate('CloudConfigSyncService')
@ObservedV2
export class CloudConfigSyncService {
  @Trace syncState: cloudSync.SyncState = cloudSync.SyncState.STOPPED
  @Trace syncError: cloudSync.ErrorType = cloudSync.ErrorType.NO_ERROR
  @Trace cacheState: cloudSync.State = cloudSync.State.STOPPED
  @Trace cacheError: cloudSync.DownloadErrorType = cloudSync.DownloadErrorType.NO_ERROR
  @Trace cacheProgress: number = 0
  @Trace lastSyncMessage: string = '未同步'
  @Trace localUpdatedAt: string = '0'
  @Trace cloudUpdatedAt: string = '0'

  private initialized: boolean = false
  private context: common.UIAbilityContext | undefined = undefined
  private readonly fileSync = new cloudSync.FileSync()
  private readonly cloudFileCache = new cloudSync.CloudFileCache()
  private reconcileTimer: number | undefined = undefined
  private pendingImportTimestamp: string | undefined = undefined
  private readonly fileSyncCallback = (pg: cloudSync.SyncProgress) => {
    this.syncState = pg.state
    this.syncError = pg.error
    if (pg.state === cloudSync.SyncState.COMPLETED) {
      if (AppManager.uiState.cloud_auto_sync) {
        this.scheduleAutoSync(300)
      }
    } else if (pg.state === cloudSync.SyncState.UPLOAD_FAILED || pg.state === cloudSync.SyncState.DOWNLOAD_FAILED) {
      this.lastSyncMessage = '同步流程异常，请检查下方错误信息'
    }
  }
  private readonly cacheProgressCallback = (pg: cloudSync.DownloadProgress) => {
    this.cacheState = pg.state
    this.cacheError = pg.error
    this.cacheProgress = pg.size > 0 ? Math.min(100, Math.trunc(pg.processed * 100 / pg.size)) : 0
    if (pg.state === cloudSync.State.COMPLETED && this.pendingImportTimestamp && pg.uri === fileUri.getUriFromPath(this.cloudDbPath())) {
      const updatedAt = this.pendingImportTimestamp
      this.pendingImportTimestamp = undefined
      if (this.importSnapshotFromCloud(updatedAt)) {
        this.lastSyncMessage = '云端快照已缓存到本地并完成导入'
      } else {
        this.lastSyncMessage = '云端快照缓存完成，但导入失败'
      }
    } else if (pg.state === cloudSync.State.FAILED) {
      this.lastSyncMessage = '云端快照缓存失败，请检查缓存错误'
      this.pendingImportTimestamp = undefined
    }
  }

  async init(context: common.UIAbilityContext): Promise<void> {
    if (this.initialized) {
      return
    }
    this.initialized = true
    this.context = context
    this.ensureLocalSyncDir()
    this.ensureCloudSyncDir()
    this.fileSync.on('progress', this.fileSyncCallback)
    this.cloudFileCache.on('progress', this.cacheProgressCallback)
    EventHelper.emitterListener(CLOUD_CONFIG_CHANGED_EVENT, () => {
      this.touchLocalMeta(this.nowTs())
      if (AppManager.uiState.cloud_auto_sync) {
        this.scheduleAutoSync()
      } else {
        this.refreshMetaState()
        this.lastSyncMessage = '本地配置已变更，等待上传或更新'
      }
    })
    if (this.readLocalMeta().updatedAt === '0') {
      const currentDbTs = this.collectLocalDbUpdatedAt()
      this.touchLocalMeta(currentDbTs === '0' ? '0' : this.nowTs())
    }
    this.refreshMetaState()
    if (AppManager.uiState.cloud_auto_sync) {
      this.safeStartFileSync('自动同步初始化')
    }
  }

  private snapshotApi(): SnapshotApi {
    return easytier as SnapshotApi
  }

  private nowTs(): string {
    return Date.now().toString()
  }

  private normalizeTimestamp(raw: string): string {
    const value = Number.parseInt(raw, 10) || 0
    if (value <= 0) {
      return '0'
    }
    if (value < 1000000000000) {
      return String(value * 1000)
    }
    return String(value)
  }

  private compareTimestamp(left: string, right: string): number {
    const a = Number.parseInt(this.normalizeTimestamp(left), 10) || 0
    const b = Number.parseInt(this.normalizeTimestamp(right), 10) || 0
    if (a === b) {
      return 0
    }
    return a > b ? 1 : -1
  }

  private ensureDir(path: string): void {
    try {
      fileIo.mkdirSync(path, true)
    } catch (_) {}
  }

  private ensureLocalSyncDir(): string {
    const dir = `${this.context?.filesDir ?? ''}/${CLOUD_SYNC_DIR}`
    this.ensureDir(dir)
    return dir
  }

  private ensureCloudSyncDir(): string {
    const dir = `${this.context?.cloudFileDir ?? ''}/${CLOUD_SYNC_DIR}`
    this.ensureDir(dir)
    return dir
  }

  private localMetaPath(): string {
    return `${this.ensureLocalSyncDir()}/${META_FILE}`
  }

  private cloudMetaPath(): string {
    return `${this.ensureCloudSyncDir()}/${META_FILE}`
  }

  private cloudDbPath(): string {
    return `${this.ensureCloudSyncDir()}/${CLOUD_DB_FILE}`
  }

  private isCloudSnapshotReady(): boolean {
    try {
      const stat = fileIo.statSync(this.cloudDbPath())
      const hasLocalEntity = (Number(stat.location) & 1) !== 0
      return stat.size > 0 && hasLocalEntity
    } catch (_) {
      return false
    }
  }

  private async ensureCloudSnapshotCached(updatedAt: string): Promise<boolean> {
    if (this.isCloudSnapshotReady()) {
      return true
    }
    this.pendingImportTimestamp = updatedAt
    this.lastSyncMessage = '云端快照仅有元数据，正在缓存到本地'
    try {
      await this.cloudFileCache.start(fileUri.getUriFromPath(this.cloudDbPath()))
      return false
    } catch (error) {
      Logger.error(`ensureCloudSnapshotCached failed: ${JSON.stringify(error)}`, this)
      this.lastSyncMessage = '触发云端快照缓存失败'
      this.pendingImportTimestamp = undefined
      return false
    }
  }

  private resetMetaState(): void {
    this.cacheState = cloudSync.State.STOPPED
    this.cacheError = cloudSync.DownloadErrorType.NO_ERROR
    this.cacheProgress = 0
    this.pendingImportTimestamp = undefined
  }

  private removeFileIfExists(path: string): void {
    try {
      fileIo.unlinkSync(path)
    } catch (_) {}
  }

  private writeTextFile(path: string, content: string): void {
    try {
      fileIo.unlinkSync(path)
    } catch (_) {}
    let file: fileIo.File | null = null
    try {
      file = fileIo.openSync(path, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE)
      fileIo.writeSync(file.fd, content)
      fileIo.closeSync(file)
    } catch (error) {
      if (file) {
        try {
          fileIo.closeSync(file)
        } catch (_) {}
      }
      throw new Error(`writeTextFile failed: ${JSON.stringify(error)}`)
    }
  }

  private readMeta(path: string): SyncMeta {
    try {
      const raw = fileIo.readTextSync(path)
      const meta = JSON.parse(raw) as SyncMeta
      return {
        version: meta.version ?? 1,
        updatedAt: this.normalizeTimestamp(meta.updatedAt ?? '0')
      }
    } catch (_) {
      return { version: 1, updatedAt: '0' }
    }
  }

  private writeMeta(path: string, updatedAt: string): void {
    const meta: SyncMeta = {
      version: 1,
      updatedAt
    }
    this.writeTextFile(path, JSON.stringify(meta))
  }

  private readLocalMeta(): SyncMeta {
    return this.readMeta(this.localMetaPath())
  }

  private readCloudMeta(): SyncMeta {
    return this.readMeta(this.cloudMetaPath())
  }

  private touchLocalMeta(updatedAt: string): void {
    this.writeMeta(this.localMetaPath(), updatedAt)
    this.refreshMetaState()
  }

  private refreshMetaState(): void {
    this.localUpdatedAt = this.readLocalMeta().updatedAt
    this.cloudUpdatedAt = this.readCloudMeta().updatedAt
  }

  private collectLocalDbUpdatedAt(): string {
    try {
      const entries = JSON.parse(easytier.listConfigs()) as StoredConfigMetaLite[]
      let latest = '0'
      for (const item of entries ?? []) {
        const updatedAt = item.updatedAt ?? '0'
        if (this.compareTimestamp(updatedAt, latest) > 0) {
          latest = this.normalizeTimestamp(updatedAt)
        }
      }
      return latest
    } catch (_) {
      return '0'
    }
  }

  private syncLocalMetaFromDb(): string {
    const latest = this.collectLocalDbUpdatedAt()
    const current = this.readLocalMeta().updatedAt
    const next = this.compareTimestamp(latest, current) > 0 ? latest : current
    this.touchLocalMeta(next)
    return next
  }

  private exportSnapshotToCloud(updatedAt: string): boolean {
    const ok = this.snapshotApi().exportConfigStoreSnapshot?.(this.cloudDbPath()) ?? false
    if (!ok) {
      return false
    }
    this.writeMeta(this.cloudMetaPath(), updatedAt)
    this.refreshMetaState()
    return true
  }

  private importSnapshotFromCloud(updatedAt: string): boolean {
    const ok = this.snapshotApi().importConfigStoreSnapshot?.(this.cloudDbPath()) ?? false
    if (!ok) {
      return false
    }
    this.writeMeta(this.localMetaPath(), updatedAt)
    AppManager.data.refreshConfigIds()
    this.refreshMetaState()
    return true
  }

  private async safeStartFileSync(reason: string): Promise<void> {
    try {
      await this.fileSync.start()
    } catch (error) {
      Logger.error(`safeStartFileSync failed reason=${reason} err=${JSON.stringify(error)}`, this)
      this.lastSyncMessage = `${reason}失败，请检查下方错误信息`
    }
  }

  async uploadToCloud(): Promise<void> {
    const localTs = this.syncLocalMetaFromDb()
    if (!this.exportSnapshotToCloud(localTs)) {
      throw new Error('export snapshot failed')
    }
    this.lastSyncMessage = '已生成本地快照并上传到云端'
    await this.safeStartFileSync('上传配置')
  }

  async updateFromCloud(): Promise<void> {
    const cloudMeta = this.readCloudMeta()
    if (cloudMeta.updatedAt === '0') {
      this.lastSyncMessage = '云端尚无配置快照'
      return
    }
    if (!await this.ensureCloudSnapshotCached(cloudMeta.updatedAt)) {
      return
    }
    if (!this.importSnapshotFromCloud(cloudMeta.updatedAt)) {
      throw new Error('import snapshot failed')
    }
    this.lastSyncMessage = '已用云端快照更新本地配置'
  }

  async syncIfNeeded(): Promise<void> {
    const localTs = this.readLocalMeta().updatedAt
    const cloudTs = this.readCloudMeta().updatedAt
    const compare = this.compareTimestamp(localTs, cloudTs)
    if (compare > 0) {
      await this.uploadToCloud()
    } else if (compare < 0) {
      await this.updateFromCloud()
    } else {
      this.lastSyncMessage = '本地与云端配置已一致'
      this.refreshMetaState()
    }
  }

  scheduleAutoSync(delay: number = 1000): void {
    if (!AppManager.uiState.cloud_auto_sync) {
      return
    }
    if (this.reconcileTimer !== undefined) {
      clearTimeout(this.reconcileTimer)
    }
    this.reconcileTimer = setTimeout(() => {
      this.reconcileTimer = undefined
      this.syncIfNeeded().catch((error: Error) => {
        Logger.error(`syncIfNeeded failed: ${JSON.stringify(error)}`, this)
        this.lastSyncMessage = '自动同步失败，请检查下方错误信息'
      })
    }, delay)
  }

  onAutoSyncChanged(enabled: boolean): void {
    this.refreshMetaState()
    if (enabled) {
      this.lastSyncMessage = '已开启自动同步，将优先采用较新的快照'
      this.safeStartFileSync('自动同步初始化')
    } else {
      this.lastSyncMessage = '已关闭自动同步'
    }
  }

  async resetAllSyncData(): Promise<void> {
    if (this.reconcileTimer !== undefined) {
      clearTimeout(this.reconcileTimer)
      this.reconcileTimer = undefined
    }
    try {
      await this.fileSync.stop()
    } catch (_) {}
    try {
      await this.cloudFileCache.stop(fileUri.getUriFromPath(this.cloudDbPath()), true)
    } catch (_) {}
    try {
      AppManager.easytier.stop()
    } catch (_) {}

    this.removeFileIfExists(this.cloudDbPath())
    this.removeFileIfExists(`${this.cloudDbPath()}-wal`)
    this.removeFileIfExists(`${this.cloudDbPath()}-shm`)
    this.removeFileIfExists(this.cloudMetaPath())
    this.removeFileIfExists(this.localMetaPath())
    this.removeFileIfExists(`${this.context?.filesDir ?? ''}/${CLOUD_DB_FILE}`)
    this.removeFileIfExists(`${this.context?.filesDir ?? ''}/${CLOUD_DB_FILE}-wal`)
    this.removeFileIfExists(`${this.context?.filesDir ?? ''}/${CLOUD_DB_FILE}-shm`)

    easytier.initConfigStore(this.context?.filesDir ?? '')
    AppManager.data.refreshConfigIds()
    AppManager.uiState.selected = undefined
    AppManager.uiState.favorite = undefined
    this.refreshMetaState()
    this.resetMetaState()
    this.syncState = cloudSync.SyncState.STOPPED
    this.syncError = cloudSync.ErrorType.NO_ERROR
    this.lastSyncMessage = '已清理本地与云端同步数据'
  }
}
