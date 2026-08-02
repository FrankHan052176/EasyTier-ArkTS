import { connection } from '@kit.NetworkKit'
import { BusinessError } from '@kit.BasicServicesKit'
import { taskpool } from '@kit.ArkTS'
import easytier from 'easytier-ohrs'
import { Logger } from '../../shared/logging/Logger'

@Concurrent
async function stopInstancesWorker(ids: string[]): Promise<boolean> {
  return easytier.stopNetworkInstance(ids)
}

@Concurrent
async function startStoredInstancesWorker(ids: string[]): Promise<boolean> {
  let started = true
  for (const id of ids) {
    if (!easytier.startKernel(id)) {
      started = false
    }
  }
  return started
}

/**
 * 在 taskpool 工作线程中执行内核软重启（停止→按存储配置拉起）。
 * 内核停止/启动是阻塞式 NAPI 调用（涉及失效网络上的套接字关闭，
 * 可能阻塞数秒），绝不能放在主线程，否则会触发 LIFECYCLE_TIMEOUT
 * 冻屏并被系统杀进程。与 EasyTierUtil 的 stopKernelWorker 同一策略。
 */
export interface NetworkRestartResult {
  stopped: boolean
  started: boolean
  cancelled: boolean
}

export async function stopStoredInstances(ids: string[]): Promise<boolean> {
  try {
    return await taskpool.execute(stopInstancesWorker, ids) as boolean
  } catch (error) {
    const err = error as Error
    Logger.error(`stop stored instances worker failed: ${err.message}`, 'VpnExtensionKernelRuntime')
    return false
  }
}

export async function startStoredInstances(ids: string[]): Promise<boolean> {
  try {
    return await taskpool.execute(startStoredInstancesWorker, ids) as boolean
  } catch (error) {
    const err = error as Error
    Logger.error(`start stored instances worker failed: ${err.message}`, 'VpnExtensionKernelRuntime')
    return false
  }
}

export async function softRestartStoredInstances(ids: string[], shouldStart: () => boolean = () => true): Promise<NetworkRestartResult> {
  const stopped = await stopStoredInstances(ids)
  if (!stopped || !shouldStart()) {
    return {
      stopped,
      started: false,
      cancelled: stopped
    }
  }
  const started = await startStoredInstances(ids)
  return {
    stopped,
    started,
    cancelled: false
  }
}

/**
 * 物理网络切换看护。
 *
 * WiFi/蜂窝等默认网络切换后，只对运行中的 EasyTier 实例执行一次
 * 内核级软重启（停止→原配置拉起）。VPN Connection 与 TUN 生命周期
 * 不属于此看护器，不能在切网回调中修改。
 *
 * 只观察 WiFi/蜂窝/以太网承载：自身 VPN 虚拟网络的出现与消失
 * 不会被当成切网（否则会造成重启死循环）。
 */
export interface NetworkChangeWatchdogOptions {
  logTarget: Object | string
  /** 返回需要看护重启的实例 configId 列表；空数组表示当前无需处理 */
  getRunningIds: () => string[]
  /** 执行内核级软重启 */
  restartInstances: (ids: string[]) => Promise<NetworkRestartResult>
}

export class NetworkChangeWatchdog {
  private readonly options: NetworkChangeWatchdogOptions
  private netConnection: connection.NetConnection | undefined = undefined
  private baselineSet: boolean = false
  private currentNetId: number = -1
  private lostSinceLast: boolean = false
  private started: boolean = false
  private restartInFlight: boolean = false
  private pendingRestart: boolean = false
  private generation: number = 0

  constructor(options: NetworkChangeWatchdogOptions) {
    this.options = options
  }

  start(): void {
    if (this.started) {
      return
    }
    this.started = true
    this.generation++
    try {
      // 不传 NetSpecifier 才是监听系统默认的非 VPN 网络。
      this.netConnection = connection.createNetConnection()
      this.netConnection.on('netAvailable', (netHandle: connection.NetHandle) => {
        this.onDefaultNetAvailable(netHandle.netId)
      })
      this.netConnection.on('netLost', (netHandle: connection.NetHandle) => {
        if (netHandle.netId === this.currentNetId) {
          this.lostSinceLast = true
          this.currentNetId = -1
          Logger.info(`default net lost netId=${netHandle.netId}`, this.options.logTarget)
        }
      })
      this.netConnection.register((error: BusinessError) => {
        if (error) {
          Logger.error(`net watchdog register failed: ${error.code} ${error.message}`, this.options.logTarget)
          return
        }
        this.captureDefaultNetworkBaseline()
      })
      Logger.info('network change watchdog started', this.options.logTarget)
    } catch (error) {
      Logger.error(`net watchdog start error: ${JSON.stringify(error)}`, this.options.logTarget)
    }
  }

  stop(): void {
    if (!this.started) {
      return
    }
    this.started = false
    this.generation++
    try {
      this.netConnection?.unregister((_error: BusinessError) => {
      })
    } catch (_) {
    }
    this.netConnection = undefined
    this.baselineSet = false
    this.currentNetId = -1
    this.lostSinceLast = false
    this.restartInFlight = false
    this.pendingRestart = false
  }

  private captureDefaultNetworkBaseline(): void {
    const generation = this.generation
    connection.getDefaultNet().then((netHandle: connection.NetHandle) => {
      if (!this.started || this.generation !== generation || this.baselineSet) {
        return
      }
      this.baselineSet = true
      this.currentNetId = netHandle.netId
      Logger.info(`default net baseline netId=${netHandle.netId}`, this.options.logTarget)
    }).catch((error: BusinessError) => {
      if (this.started && this.generation === generation) {
        Logger.info(`default net baseline unavailable: ${error.code} ${error.message}`, this.options.logTarget)
      }
    })
  }

  private onDefaultNetAvailable(netId: number): void {
    if (!this.started) {
      return
    }
    if (!this.baselineSet) {
      // 启动时的首个物理网络：仅作为基线，不触发重启
      this.baselineSet = true
      this.currentNetId = netId
      Logger.info(`default net baseline netId=${netId}`, this.options.logTarget)
      return
    }
    const switched = netId !== this.currentNetId || this.lostSinceLast
    this.currentNetId = netId
    this.lostSinceLast = false
    if (!switched) {
      return
    }
    Logger.info(`default net switched to netId=${netId}`, this.options.logTarget)
    this.performRestart(`default net switched to ${netId}`)
  }

  private performRestart(reason: string): void {
    if (!this.started) {
      return
    }
    if (this.restartInFlight) {
      this.pendingRestart = true
      Logger.info(`net watchdog restart queued reason=${reason}`, this.options.logTarget)
      return
    }
    const ids = this.options.getRunningIds()
    if (ids.length === 0) {
      return
    }
    const generation = this.generation
    this.pendingRestart = false
    this.restartInFlight = true
    Logger.info(`soft-restarting instances reason=${reason}: ${ids.join(',')}`, this.options.logTarget)
    this.options.restartInstances(ids).then((result: NetworkRestartResult) => {
      if (!this.started || this.generation !== generation) {
        return
      }
      Logger.info(`net watchdog restart result stopped=${result.stopped} started=${result.started} cancelled=${result.cancelled}`, this.options.logTarget)
    }).catch((error: Error) => {
      if (!this.started || this.generation !== generation) {
        return
      }
      Logger.error(`net watchdog restart error: ${error.message}`, this.options.logTarget)
    }).finally(() => {
      if (this.generation !== generation) {
        return
      }
      this.restartInFlight = false
      if (this.pendingRestart) {
        this.pendingRestart = false
        this.performRestart('network changed while restart was running')
      }
    })
  }
}
