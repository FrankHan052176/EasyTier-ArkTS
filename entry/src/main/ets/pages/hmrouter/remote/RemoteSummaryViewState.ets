import { RemoteConfigMeta, RemoteRuntimeInstanceLite, RemoteSummary } from '../../../services/remote/RemoteManageTypes'

function runtimeRowKey(instance: RemoteRuntimeInstanceLite): string {
  return instance.instanceId || instance.configId
}

function runtimeDisplayName(instance: RemoteRuntimeInstanceLite): string {
  if (instance.displayName && instance.displayName.length > 0 &&
    instance.displayName !== instance.configId && instance.displayName !== instance.instanceId) {
    return instance.displayName
  }
  return '未命名实例'
}

@ObservedV2
export class RemoteConfigRowModel {
  @Trace configId: string = ''
  @Trace displayName: string = ''
  @Trace favorite: boolean = false
  @Trace running: boolean = false

  update(config: RemoteConfigMeta): boolean {
    const nextDisplayName = config.displayName || config.configId
    const nextFavorite = !!config.favorite
    const nextRunning = !!config.running
    const changed = this.configId !== config.configId || this.displayName !== nextDisplayName ||
      this.favorite !== nextFavorite || this.running !== nextRunning
    this.configId = config.configId
    this.displayName = nextDisplayName
    this.favorite = nextFavorite
    this.running = nextRunning
    return changed
  }
}

@ObservedV2
export class RemoteRuntimeRowModel {
  @Trace rowKey: string = ''
  @Trace configId: string = ''
  @Trace instanceId: string = ''
  @Trace displayName: string = ''
  @Trace virtualIpv4: string = ''
  @Trace peerCount: number = 0
  @Trace routeCount: number = 0

  update(instance: RemoteRuntimeInstanceLite): boolean {
    const nextKey = runtimeRowKey(instance)
    const nextDisplayName = runtimeDisplayName(instance)
    const nextIpv4 = instance.myNodeInfo?.virtualIpv4 ?? '未分配 IPv4'
    const nextPeerCount = instance.peerCount
    const nextRouteCount = instance.routeCount
    const changed = this.rowKey !== nextKey || this.configId !== instance.configId ||
      this.instanceId !== instance.instanceId || this.displayName !== nextDisplayName ||
      this.virtualIpv4 !== nextIpv4 || this.peerCount !== nextPeerCount || this.routeCount !== nextRouteCount
    this.rowKey = nextKey
    this.configId = instance.configId
    this.instanceId = instance.instanceId
    this.displayName = nextDisplayName
    this.virtualIpv4 = nextIpv4
    this.peerCount = nextPeerCount
    this.routeCount = nextRouteCount
    return changed
  }
}

interface RemoteSummaryRowModel<T> {
  update(value: T): boolean
}

abstract class RemoteSummaryDataSource<T, R extends RemoteSummaryRowModel<T>> implements IDataSource {
  private listeners: DataChangeListener[] = []
  protected items: R[] = []

  totalCount(): number {
    return this.items.length
  }

  getData(index: number): R {
    return this.items[index]
  }

  setItems(values: T[]): void {
    const current = new Map<string, R>()
    this.items.forEach((item) => {
      current.set(this.rowKey(item), item)
    })
    const nextItems: R[] = []
    const changedIndexes: number[] = []
    let structuralChanged = this.items.length !== values.length
    values.forEach((value, index) => {
      const key = this.valueKey(value)
      let item = current.get(key)
      if (!item) {
        item = this.createRow()
        structuralChanged = true
      } else if (this.items[index] && this.rowKey(this.items[index]) !== key) {
        structuralChanged = true
      }
      if (item.update(value)) {
        changedIndexes.push(index)
      }
      nextItems.push(item)
    })
    this.items = nextItems
    if (structuralChanged) {
      this.notifyDataReload()
      return
    }
    changedIndexes.forEach((index) => {
      this.notifyDataChange(index)
    })
  }

  clear(): void {
    if (this.items.length === 0) {
      return
    }
    this.items = []
    this.notifyDataReload()
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    if (this.listeners.indexOf(listener) < 0) {
      this.listeners.push(listener)
    }
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    const index = this.listeners.indexOf(listener)
    if (index >= 0) {
      this.listeners.splice(index, 1)
    }
  }

  private notifyDataReload(): void {
    this.listeners.forEach((listener) => {
      listener.onDataReloaded()
    })
  }

  private notifyDataChange(index: number): void {
    this.listeners.forEach((listener) => {
      listener.onDataChange(index)
    })
  }

  protected abstract valueKey(value: T): string

  protected abstract rowKey(item: R): string

  protected abstract createRow(): R
}

@ObservedV2
export class RemoteConfigDataSource extends RemoteSummaryDataSource<RemoteConfigMeta, RemoteConfigRowModel> {
  isRunning(configId: string): boolean {
    const item = this.items.find((value) => value.configId === configId)
    return !!item?.running
  }

  protected valueKey(config: RemoteConfigMeta): string {
    return config.configId
  }

  protected rowKey(item: RemoteConfigRowModel): string {
    return item.configId
  }

  protected createRow(): RemoteConfigRowModel {
    return new RemoteConfigRowModel()
  }
}

@ObservedV2
export class RemoteRuntimeDataSource extends RemoteSummaryDataSource<RemoteRuntimeInstanceLite, RemoteRuntimeRowModel> {
  protected valueKey(instance: RemoteRuntimeInstanceLite): string {
    return runtimeRowKey(instance)
  }

  protected rowKey(item: RemoteRuntimeRowModel): string {
    return item.rowKey
  }

  protected createRow(): RemoteRuntimeRowModel {
    return new RemoteRuntimeRowModel()
  }
}

@ObservedV2
export class RemoteSummaryViewState {
  @Trace deviceName: string = ''
  @Trace coreVersion: string = ''
  @Trace configCount: number = 0
  @Trace runningCount: number = 0
  @Trace runtimeDurationText: string = '未运行'
  @Trace memoryUsageText: string = '未记录'
  @Trace extMode: boolean = false
  @Trace devMode: boolean = false
  @Trace coreLog: boolean = false
  @Trace debugLog: boolean = false
  @Trace distributePerm: boolean = false

  private summary: RemoteSummary | undefined = undefined
  configs: RemoteConfigDataSource = new RemoteConfigDataSource()
  runtimes: RemoteRuntimeDataSource = new RemoteRuntimeDataSource()

  apply(summary: RemoteSummary | undefined): void {
    this.summary = summary
    if (!summary) {
      this.clear()
      return
    }
    this.deviceName = summary.deviceName ?? ''
    this.coreVersion = summary.coreVersion ?? ''
    this.configCount = summary.runtime?.configCount ?? summary.configs.length
    this.runningCount = summary.runtime?.runningCount ?? summary.runtime?.runningConfigs?.length ?? 0
    this.runtimeDurationText = summary.runtime?.runtimeDurationText ?? '未运行'
    this.memoryUsageText = summary.runtime?.memoryUsageText ?? '未记录'
    this.extMode = summary.settings?.ext_mode ?? false
    this.devMode = summary.settings?.dev ?? false
    this.coreLog = summary.settings?.core_log ?? false
    this.debugLog = summary.settings?.debug_log ?? false
    this.distributePerm = summary.settings?.distributePerm ?? false
    this.configs.setItems(this.withRuntimeFlags(summary))
    this.runtimes.setItems(summary.runtime?.runningConfigs ?? [])
  }

  clear(): void {
    this.summary = undefined
    this.deviceName = ''
    this.coreVersion = ''
    this.configCount = 0
    this.runningCount = 0
    this.runtimeDurationText = '未运行'
    this.memoryUsageText = '未记录'
    this.extMode = false
    this.devMode = false
    this.coreLog = false
    this.debugLog = false
    this.distributePerm = false
    this.configs.clear()
    this.runtimes.clear()
  }

  isConfigRunning(configId: string): boolean {
    if (!configId) {
      return false
    }
    if (this.configs.isRunning(configId)) {
      return true
    }
    const summary = this.summary
    if (!summary) {
      return false
    }
    const metaRunning = (summary.configs ?? []).some((config) => {
      return config.configId === configId && !!config.running
    })
    if (metaRunning) {
      return true
    }
    return (summary.runtime?.runningConfigs ?? []).some((instance) => {
      return instance.configId === configId || instance.instanceId === configId
    })
  }

  private withRuntimeFlags(summary: RemoteSummary): RemoteConfigMeta[] {
    const runningIds = new Set<string>()
    ;(summary.runtime?.runningConfigs ?? []).forEach((instance) => {
      if (instance.configId) {
        runningIds.add(instance.configId)
      }
      if (instance.instanceId) {
        runningIds.add(instance.instanceId)
      }
    })
    return (summary.configs ?? []).map((config) => {
      return {
        configId: config.configId,
        displayName: config.displayName,
        favorite: config.favorite,
        running: !!config.running || runningIds.has(config.configId)
      } as RemoteConfigMeta
    })
  }
}
