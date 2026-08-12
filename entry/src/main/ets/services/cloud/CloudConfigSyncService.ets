import { common } from '@kit.AbilityKit'
import { JSON } from '@kit.ArkTS'
import { BusinessError } from '@kit.BasicServicesKit'
import { cloudSync, fileIo, fileUri } from '@kit.CoreFileKit'
import easytier from 'easytier-ohrs'
import { AppManager } from '../../AppManager'
import { CLOUD_CONFIG_CHANGED_EVENT } from '../../ConfigSyncUtil'
import { isCloudResetting, setCloudResetting } from './CloudMutationGate'
import { EventHelper } from '../../util/EventHelper'
import { Logger, LogLocate } from '../../shared/logging/Logger'
import { FAVORITE_CARD_REFRESH_EVENT } from '../form/FavoriteCardState'

const CLOUD_SYNC_DIR = 'easytier-sync'
const CLOUD_DB_FILE = 'easytier-config-store.db'
const META_FILE = 'sync-meta.json'
const CLOUD_STATUS_NOT_READY = 22400001
const CLOUD_READY_RETRY_DELAYS_MS: number[] = [1000, 3000, 10000, 30000]

export function cloudSyncStartErrorMessage(code: number, reason: string): string {
  switch (code) {
    case CLOUD_STATUS_NOT_READY:
      return `${reason}暂不可用：云空间服务尚未就绪，请确认已登录华为账号并稍后重试`
    case 22400002:
      return `${reason}暂不可用：当前网络不可用，请检查网络后重试`
    case 22400003:
      return `${reason}暂不可用：当前电量过低，请充电后重试`
    case 13600001:
      return `${reason}失败：云空间系统服务通信异常，请稍后重试`
    default:
      return code > 0 ? `${reason}失败（错误码 ${code}），请稍后重试` : `${reason}失败，请稍后重试`
  }
}

interface SyncMeta {
  version: number
  updatedAt: string
}

interface SnapshotImportResult {
  ok: boolean
  errorCode: string
  errorMessage: string
  snapshotInvalid: boolean
}

interface PendingImportRequest {
  updatedAt: string
  successMessage: string
}

interface FileSyncStartResult {
  completed: boolean
  errorCode: number
  errorMessage: string
}

interface SnapshotApi extends ESObject {
  resetConfigStore?: () => boolean
  exportConfigStoreSnapshot?: (targetPath: string) => boolean
  importConfigStoreSnapshot?: (sourcePath: string) => boolean
  importConfigStoreSnapshotWithResult?: (sourcePath: string) => SnapshotImportResult
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
  private resettingSyncData: boolean = false
  private context: common.UIAbilityContext | undefined = undefined
  private readonly fileSync = new cloudSync.FileSync()
  private readonly cloudFileCache = new cloudSync.CloudFileCache()
  private reconcileTimer: number | undefined = undefined
  private pendingImport: PendingImportRequest | undefined = undefined
  private syncInFlight: boolean = false
  private syncProgressGeneration: number = 0
  private fileSyncStartInFlight: Promise<FileSyncStartResult> | undefined = undefined
  private cloudReadyRetryTimer: number | undefined = undefined
  private cloudReadyRetryAttempt: number = 0
  private cloudReadyRetryGeneration: number = 0
  private readonly fileSyncCallback = (pg: cloudSync.SyncProgress) => {
    this.syncProgressGeneration++
    this.syncState = pg.state
    this.syncError = pg.error
    if (this.resettingSyncData) {
      return
    }
    if (pg.state === cloudSync.SyncState.COMPLETED) {
      this.cancelCloudReadyRetry()
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
    if (this.resettingSyncData) {
      return
    }
    if (pg.uri !== fileUri.getUriFromPath(this.cloudDbPath())) {
      return
    }
    if (pg.state === cloudSync.State.COMPLETED && this.pendingImport) {
      void this.resumePendingImport(this.pendingImport)
    } else if (pg.state === cloudSync.State.FAILED) {
      this.lastSyncMessage = '云端快照缓存失败，请检查缓存错误'
      this.pendingImport = undefined
    }
  }
  private readonly configChangedCallback = () => {
    if (this.resettingSyncData || isCloudResetting()) {
      return
    }
    this.touchLocalMeta(this.nowTs())
    if (AppManager.uiState.cloud_auto_sync) {
      this.scheduleAutoSync()
    } else {
      this.refreshMetaState()
      this.lastSyncMessage = '本地配置已变更，等待上传或更新'
    }
  }

  async init(context: common.UIAbilityContext): Promise<void> {
    if (this.initialized) {
      return
    }
    this.context = context
    this.ensureLocalSyncDir()
    this.ensureCloudSyncDir()
    if (this.readLocalMeta().updatedAt === '0') {
      const currentDbTs = this.collectLocalDbUpdatedAt()
      this.touchLocalMeta(currentDbTs)
    }
    this.refreshMetaState()
    this.fileSync.on('progress', this.fileSyncCallback)
    this.cloudFileCache.on('progress', this.cacheProgressCallback)
    EventHelper.emitterListener(CLOUD_CONFIG_CHANGED_EVENT, this.configChangedCallback)
    if (AppManager.uiState.cloud_auto_sync) {
      this.beginCloudReadySync()
    }
    this.initialized = true
  }

  private snapshotApi(): SnapshotApi {
    return easytier as SnapshotApi
  }

  private requireContext(): common.UIAbilityContext {
    if (!this.context || !this.context.filesDir || this.context.filesDir.length === 0) {
      throw new Error('CloudConfigSyncService context.filesDir is not initialized')
    }
    return this.context
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
    const dir = `${this.requireContext().filesDir}/${CLOUD_SYNC_DIR}`
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

  private localExportSnapshotPath(): string {
    return `${this.ensureLocalSyncDir()}/upload-${CLOUD_DB_FILE}`
  }

  private localImportSnapshotPath(): string {
    return `${this.ensureLocalSyncDir()}/download-${CLOUD_DB_FILE}`
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

  private async ensureCloudSnapshotCached(updatedAt: string, successMessage: string): Promise<boolean> {
    if (this.isCloudSnapshotReady()) {
      return true
    }
    this.pendingImport = {
      updatedAt,
      successMessage
    }
    this.lastSyncMessage = '云端快照仅有元数据，正在缓存到本地'
    try {
      await this.cloudFileCache.start(fileUri.getUriFromPath(this.cloudDbPath()))
      return false
    } catch (error) {
      Logger.error(`ensureCloudSnapshotCached failed: ${JSON.stringify(error)}`, this)
      this.lastSyncMessage = '触发云端快照缓存失败'
      this.pendingImport = undefined
      return false
    }
  }

  private resetMetaState(): void {
    this.cacheState = cloudSync.State.STOPPED
    this.cacheError = cloudSync.DownloadErrorType.NO_ERROR
    this.cacheProgress = 0
    this.pendingImport = undefined
  }

  private shouldImportCloudSnapshot(localUpdatedAt: string, cloudUpdatedAt: string): boolean {
    return this.compareTimestamp(cloudUpdatedAt, localUpdatedAt) > 0
  }

  private removeFileIfExists(path: string): void {
    try {
      fileIo.unlinkSync(path)
    } catch (_) {}
  }

  private copyFileReplacing(src: string, dest: string): void {
    const tempDest = `${dest}.tmp`
    this.removeFileIfExists(tempDest)
    try {
      fileIo.copyFileSync(src, tempDest)
      this.removeFileIfExists(dest)
      fileIo.renameSync(tempDest, dest)
    } catch (error) {
      this.removeFileIfExists(tempDest)
      throw new Error(`copyFileReplacing failed: ${JSON.stringify(error)}`)
    }
  }

  private writeTextFile(path: string, content: string): void {
    const tempPath = `${path}.tmp`
    this.removeFileIfExists(tempPath)
    let file: fileIo.File | null = null
    try {
      file = fileIo.openSync(tempPath, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE)
      fileIo.writeSync(file.fd, content)
      fileIo.closeSync(file)
      this.removeFileIfExists(path)
      fileIo.renameSync(tempPath, path)
    } catch (error) {
      if (file) {
        try {
          fileIo.closeSync(file)
        } catch (_) {}
      }
      this.removeFileIfExists(tempPath)
      throw new Error(`writeTextFile failed: ${JSON.stringify(error)}`)
    }
  }

  private async runExclusive<T>(action: () => Promise<T>): Promise<T | undefined> {
    if (this.syncInFlight) {
      this.lastSyncMessage = '同步任务正在执行，请稍候'
      return undefined
    }
    this.syncInFlight = true
    try {
      return await action()
    } finally {
      this.syncInFlight = false
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
    const localSnapshotPath = this.localExportSnapshotPath()
    this.removeFileIfExists(localSnapshotPath)
    const ok = this.snapshotApi().exportConfigStoreSnapshot?.(localSnapshotPath) ?? false
    if (!ok) {
      return false
    }
    try {
      this.copyFileReplacing(localSnapshotPath, this.cloudDbPath())
    } catch (error) {
      Logger.error(`exportSnapshotToCloud copy failed: ${JSON.stringify(error)}`, this)
      this.removeFileIfExists(localSnapshotPath)
      return false
    }
    this.removeFileIfExists(localSnapshotPath)
    this.writeMeta(this.cloudMetaPath(), updatedAt)
    this.refreshMetaState()
    return true
  }

  private buildSnapshotImportResult(ok: boolean, errorCode: string = '', errorMessage: string = '',
    snapshotInvalid: boolean = false): SnapshotImportResult {
    return { ok, errorCode, errorMessage, snapshotInvalid }
  }

  private logSnapshotImportFailure(context: string, result: SnapshotImportResult): void {
    Logger.error(`${context} failed code=${result.errorCode} invalid=${result.snapshotInvalid} msg=${result.errorMessage}`, this)
  }

  private importSnapshotFromCloud(updatedAt: string): SnapshotImportResult {
    const restoreGate = isCloudResetting()
    setCloudResetting(true)
    const localSnapshotPath = this.localImportSnapshotPath()
    try {
      this.removeFileIfExists(localSnapshotPath)
      this.copyFileReplacing(this.cloudDbPath(), localSnapshotPath)
      const result = this.snapshotApi().importConfigStoreSnapshotWithResult?.(localSnapshotPath)
        ?? this.buildSnapshotImportResult(this.snapshotApi().importConfigStoreSnapshot?.(localSnapshotPath) ?? false)
      this.removeFileIfExists(localSnapshotPath)
      if (!result.ok) {
        return result
      }
      this.writeMeta(this.localMetaPath(), updatedAt)
      AppManager.data.refreshConfigIds()
      AppManager.preference.refreshFavoriteFromStore()
      this.refreshMetaState()
      return this.buildSnapshotImportResult(true)
    } catch (error) {
      Logger.error(`importSnapshotFromCloud failed: ${JSON.stringify(error)}`, this)
      this.removeFileIfExists(localSnapshotPath)
      return this.buildSnapshotImportResult(false, 'cloud_import_failed', JSON.stringify(error))
    } finally {
      setCloudResetting(restoreGate)
    }
  }

  private async resumePendingImport(request: PendingImportRequest): Promise<void> {
    const resumed = await this.runExclusive(async () => {
      if (this.pendingImport !== request) {
        return
      }
      if (!this.isCloudSnapshotReady()) {
        this.lastSyncMessage = '云端快照缓存尚未完成，等待继续导入'
        return
      }
      const localTs = this.syncLocalMetaFromDb()
      const cloudTs = this.readCloudMeta().updatedAt
      const effectiveCloudTs = this.compareTimestamp(cloudTs, request.updatedAt) > 0 ? cloudTs : request.updatedAt
      if (!this.shouldImportCloudSnapshot(localTs, effectiveCloudTs)) {
        this.pendingImport = undefined
        this.refreshMetaState()
        this.lastSyncMessage = '缓存期间本地配置已更新，已跳过较旧的云端快照'
        return
      }
      const importResult = this.importSnapshotFromCloud(effectiveCloudTs)
      if (!importResult.ok) {
        this.pendingImport = undefined
        this.logSnapshotImportFailure('resumePendingImport', importResult)
        this.lastSyncMessage = '云端快照格式不兼容或导入失败；已保留云端备份，请稍后重试'
        return
      }
      this.pendingImport = undefined
      this.lastSyncMessage = request.successMessage
    })
    if (resumed === undefined && this.pendingImport === request) {
      this.lastSyncMessage = '云端快照已缓存，等待当前同步任务结束后导入'
      setTimeout(() => {
        void this.resumePendingImport(request)
      }, 200)
    }
  }

  private fileSyncStartFailure(error: Object): FileSyncStartResult {
    const businessError = error as BusinessError
    const errorCode = typeof businessError.code === 'number' ? businessError.code : 0
    const errorMessage = typeof businessError.message === 'string' ? businessError.message : String(error)
    return { completed: false, errorCode, errorMessage }
  }

  private async startFileSync(): Promise<FileSyncStartResult> {
    const startGeneration = this.syncProgressGeneration
    try {
      await this.fileSync.start()
      const completed = await this.waitForSyncCompletion(15000, startGeneration)
      return { completed, errorCode: 0, errorMessage: '' }
    } catch (error) {
      return this.fileSyncStartFailure(error)
    }
  }

  private async safeStartFileSync(reason: string, requireNewCycle: boolean = false): Promise<FileSyncStartResult> {
    if (requireNewCycle && this.fileSyncStartInFlight !== undefined) {
      const previous = this.fileSyncStartInFlight
      await previous
      if (this.fileSyncStartInFlight === previous) {
        this.fileSyncStartInFlight = undefined
      }
    }
    if (this.fileSyncStartInFlight === undefined) {
      this.fileSyncStartInFlight = this.startFileSync()
    }
    const inFlight = this.fileSyncStartInFlight
    let result: FileSyncStartResult
    try {
      result = await inFlight
    } finally {
      if (this.fileSyncStartInFlight === inFlight) {
        this.fileSyncStartInFlight = undefined
      }
    }
    if (result.completed) {
      return result
    }
    if (result.errorCode > 0) {
      Logger.error(`safeStartFileSync failed reason=${reason} code=${result.errorCode} message=${result.errorMessage}`, this)
      this.lastSyncMessage = cloudSyncStartErrorMessage(result.errorCode, reason)
    } else {
      this.lastSyncMessage = `${reason}未完成，请检查同步状态`
    }
    return result
  }

  private async waitForFileSyncCycle(): Promise<void> {
    const inFlight = this.fileSyncStartInFlight
    if (inFlight !== undefined) {
      await inFlight
    }
  }

  private cancelCloudReadyRetry(): void {
    this.cloudReadyRetryGeneration++
    this.cloudReadyRetryAttempt = 0
    if (this.cloudReadyRetryTimer !== undefined) {
      clearTimeout(this.cloudReadyRetryTimer)
      this.cloudReadyRetryTimer = undefined
    }
  }

  private beginCloudReadySync(): void {
    this.cancelCloudReadyRetry()
    const generation = this.cloudReadyRetryGeneration
    void this.retryCloudReadySync(generation)
  }

  private scheduleCloudReadyRetry(generation: number): void {
    if (!AppManager.uiState.cloud_auto_sync || this.resettingSyncData ||
      generation !== this.cloudReadyRetryGeneration || this.cloudReadyRetryTimer !== undefined) {
      return
    }
    if (this.cloudReadyRetryAttempt >= CLOUD_READY_RETRY_DELAYS_MS.length) {
      this.lastSyncMessage = '云空间服务仍未就绪，请确认已登录华为账号后手动重试'
      return
    }
    const delay = CLOUD_READY_RETRY_DELAYS_MS[this.cloudReadyRetryAttempt]
    this.cloudReadyRetryAttempt++
    this.lastSyncMessage = '云空间服务尚未就绪，将稍后自动重试'
    this.cloudReadyRetryTimer = setTimeout(() => {
      this.cloudReadyRetryTimer = undefined
      void this.retryCloudReadySync(generation)
    }, delay)
  }

  private async retryCloudReadySync(generation: number): Promise<void> {
    if (!AppManager.uiState.cloud_auto_sync || this.resettingSyncData ||
      generation !== this.cloudReadyRetryGeneration) {
      return
    }
    const result = await this.safeStartFileSync('自动同步初始化')
    if (generation !== this.cloudReadyRetryGeneration) {
      if (!AppManager.uiState.cloud_auto_sync) {
        this.lastSyncMessage = '已关闭自动同步'
      }
      return
    }
    if (result.completed) {
      this.cancelCloudReadyRetry()
    } else if (result.errorCode === CLOUD_STATUS_NOT_READY) {
      this.scheduleCloudReadyRetry(generation)
    }
  }

  private async waitForSyncCompletion(timeoutMs: number, sinceGeneration: number): Promise<boolean> {
    const startedAt = Date.now()
    while (Date.now() - startedAt < timeoutMs) {
      if (this.syncProgressGeneration > sinceGeneration && this.syncState === cloudSync.SyncState.COMPLETED) {
        return true
      }
      if (this.syncProgressGeneration > sinceGeneration &&
        (this.syncState === cloudSync.SyncState.UPLOAD_FAILED || this.syncState === cloudSync.SyncState.DOWNLOAD_FAILED)) {
        return false
      }
      await new Promise<void>((resolve) => {
        setTimeout(() => resolve(), 100)
      })
    }
    return this.syncProgressGeneration > sinceGeneration && this.syncState === cloudSync.SyncState.COMPLETED
  }

  isResettingSyncData(): boolean {
    return this.resettingSyncData
  }

  async uploadToCloud(): Promise<void> {
    await this.runExclusive(async () => {
      await this.waitForFileSyncCycle()
      const localTs = this.syncLocalMetaFromDb()
      if (!this.exportSnapshotToCloud(localTs)) {
        throw new Error('export snapshot failed')
      }
      if (!(await this.safeStartFileSync('上传配置', true)).completed) {
        throw new Error('file sync upload did not complete')
      }
      this.lastSyncMessage = '已生成本地快照并上传到云端'
    })
  }

  async updateFromCloud(): Promise<void> {
    await this.runExclusive(async () => {
      await this.waitForFileSyncCycle()
      const cloudMeta = this.readCloudMeta()
      if (cloudMeta.updatedAt === '0') {
        this.lastSyncMessage = '云端尚无配置快照'
        return
      }
      const localTs = this.syncLocalMetaFromDb()
      if (!this.shouldImportCloudSnapshot(localTs, cloudMeta.updatedAt)) {
        this.lastSyncMessage = this.compareTimestamp(localTs, cloudMeta.updatedAt) === 0
          ? '本地与云端配置已一致'
          : '云端快照较旧，已拒绝覆盖本地配置'
        this.refreshMetaState()
        return
      }
      if (!await this.ensureCloudSnapshotCached(cloudMeta.updatedAt, '已用云端快照更新本地配置')) {
        return
      }
      const importResult = this.importSnapshotFromCloud(cloudMeta.updatedAt)
      if (!importResult.ok) {
        this.logSnapshotImportFailure('updateFromCloud', importResult)
        this.lastSyncMessage = '云端快照格式不兼容或导入失败；已保留云端备份，请稍后重试'
        return
      }
      this.lastSyncMessage = '已用云端快照更新本地配置'
    })
  }

  async syncIfNeeded(): Promise<void> {
    await this.runExclusive(async () => {
      await this.waitForFileSyncCycle()
      const localTs = this.syncLocalMetaFromDb()
      const cloudTs = this.readCloudMeta().updatedAt
      const compare = this.compareTimestamp(localTs, cloudTs)
      if (compare > 0) {
        if (!this.exportSnapshotToCloud(localTs)) {
          throw new Error('export snapshot failed')
        }
        const result = await this.safeStartFileSync('自动同步上传', true)
        if (result.completed) {
          this.lastSyncMessage = '已自动上传较新的本地快照'
        } else if (result.errorCode === CLOUD_STATUS_NOT_READY) {
          this.scheduleCloudReadyRetry(this.cloudReadyRetryGeneration)
        }
      } else if (compare < 0) {
        const cloudMeta = this.readCloudMeta()
        if (!await this.ensureCloudSnapshotCached(cloudMeta.updatedAt, '已自动使用较新的云端快照更新本地')) {
          return
        }
        const importResult = this.importSnapshotFromCloud(cloudMeta.updatedAt)
        if (!importResult.ok) {
          this.logSnapshotImportFailure('syncIfNeeded', importResult)
          this.lastSyncMessage = '云端快照格式不兼容或导入失败；已保留云端备份，请稍后重试'
          return
        }
        this.lastSyncMessage = '已自动使用较新的云端快照更新本地'
      } else {
        this.lastSyncMessage = '本地与云端配置已一致'
        this.refreshMetaState()
      }
    })
  }

  scheduleAutoSync(delay: number = 1000): void {
    if (!AppManager.uiState.cloud_auto_sync || this.resettingSyncData) {
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
      this.beginCloudReadySync()
    } else {
      this.cancelCloudReadyRetry()
      this.lastSyncMessage = '已关闭自动同步'
    }
  }

  async resetAllSyncData(): Promise<void> {
    await this.runExclusive(async () => {
      const context = this.requireContext()
      this.resettingSyncData = true
      setCloudResetting(true)
      this.cancelCloudReadyRetry()
      if (this.reconcileTimer !== undefined) {
        clearTimeout(this.reconcileTimer)
        this.reconcileTimer = undefined
      }
      this.pendingImport = undefined
      this.resetMetaState()
      try {
        await this.waitForFileSyncCycle()
        try {
          await this.cloudFileCache.stop(fileUri.getUriFromPath(this.cloudDbPath()), true)
        } catch (_) {}
        try {
          await AppManager.easytier.stopAndWait()
        } catch (_) {}
        await AppManager.preference.clearLegacyPreferenceSources(context)

        const resetOk = this.snapshotApi().resetConfigStore?.() ?? false
        if (!resetOk) {
          throw new Error('resetConfigStore failed')
        }
        this.removeFileIfExists(this.cloudDbPath())
        this.removeFileIfExists(`${this.cloudDbPath()}-wal`)
        this.removeFileIfExists(`${this.cloudDbPath()}-shm`)
        this.removeFileIfExists(this.cloudMetaPath())
        this.removeFileIfExists(this.localMetaPath())
        this.removeFileIfExists(this.localExportSnapshotPath())
        this.removeFileIfExists(this.localImportSnapshotPath())

        const synced = (await this.safeStartFileSync('重置同步文件', true)).completed
        try {
          await this.fileSync.stop()
        } catch (_) {}
        if (!easytier.initConfigStore(context.filesDir)) {
          throw new Error('initConfigStore failed after reset')
        }
        AppManager.data.refreshConfigIds()
        AppManager.uiState.selected = undefined
        AppManager.uiState.favorite = undefined
        EventHelper.emitterPublish(FAVORITE_CARD_REFRESH_EVENT)
        this.refreshMetaState()
        this.resetMetaState()
        this.syncState = cloudSync.SyncState.STOPPED
        this.syncError = cloudSync.ErrorType.NO_ERROR
        this.lastSyncMessage = synced
          ? '已清理本地与云端同步数据'
          : '已清理本地同步数据，云端删除同步结果未确认'
      } finally {
        this.resettingSyncData = false
        setCloudResetting(false)
      }
    })
  }
}
