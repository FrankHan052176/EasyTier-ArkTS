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
async function startStoredInstancesWorker(ids: string[]): Promise<void> {
  for (const id of ids) {
    easytier.startKernel(id)
  }
}

@Concurrent
async function startWithConfigWorker(cfgJson: string): Promise<boolean> {
  return easytier.parseNetworkConfig(cfgJson) && easytier.runNetworkInstance(cfgJson)
}

const RESTART_SETTLE_MS = 500

function settle(): Promise<void> {
  return new Promise<void>((resolve) => {
    setTimeout(resolve, RESTART_SETTLE_MS)
  })
}

/**
 * 在 taskpool 工作线程中执行内核软重启（停止→按存储配置拉起）。
 * 内核停止/启动是阻塞式 NAPI 调用（涉及失效网络上的套接字关闭，
 * 可能阻塞数秒），绝不能放在主线程，否则会触发 LIFECYCLE_TIMEOUT
 * 冻屏并被系统杀进程。与 EasyTierUtil 的 stopKernelWorker 同一策略。
 */
export async function softRestartStoredInstances(ids: string[]): Promise<void> {
  await taskpool.execute(stopInstancesWorker, ids)
  await settle()
  await taskpool.execute(startStoredInstancesWorker, ids)
}

/** ext（子进程）模式：以持有的原始配置 JSON 重启单实例，同样走 taskpool */
export async function softRestartWithConfig(id: string, cfgJson: string): Promise<void> {
  await taskpool.execute(stopInstancesWorker, [id])
  await settle()
  await taskpool.execute(startWithConfigWorker, cfgJson)
}

/**
 * 物理网络切换看护。
 *
 * 背景：WiFi/蜂窝切换后，内核既有连接绑定在已失效的网络上，
 * 自动重连大概率卡死（尤其是曾执行过 protectProcessNet 时，
 * 进程套接字仍固定在旧网络句柄上）。内核代码不可修改，因此在
 * 应用层监听“物理承载网络”的变化，切网后对运行中的实例做一次
 * 内核级软重启（停止→原配置拉起），并给上层机会先重新执行
 * 网络保护绑定。
 *
 * 只观察 WiFi/蜂窝/以太网承载：自身 VPN 虚拟网络的出现与消失
 * 不会被当成切网（否则会造成重启死循环）。
 */
export interface NetworkChangeWatchdogOptions {
  logTarget: Object | string
  /** 返回需要看护重启的实例 configId 列表；空数组表示当前无需处理 */
  getRunningIds: () => string[]
  /** 执行内核级软重启 */
  restartInstances: (ids: string[]) => void
  /** 重启前的准备动作（如重新 protectProcessNet），完成后必须调用 done */
  beforeRestart?: (done: () => void) => void
}

const SWITCH_DEBOUNCE_MS = 1500
const RESTART_COOLDOWN_MS = 8000

export class NetworkChangeWatchdog {
  private readonly options: NetworkChangeWatchdogOptions
  private netConnection: connection.NetConnection | undefined = undefined
  private baselineSet: boolean = false
  private currentNetId: number = -1
  private lostSinceLast: boolean = false
  private debounceTimer: number = -1
  private lastRestartAt: number = 0
  private started: boolean = false

  constructor(options: NetworkChangeWatchdogOptions) {
    this.options = options
  }

  start(): void {
    if (this.started) {
      return
    }
    this.started = true
    try {
      this.netConnection = connection.createNetConnection({
        netCapabilities: {
          bearerTypes: [
            connection.NetBearType.BEARER_CELLULAR,
            connection.NetBearType.BEARER_WIFI,
            connection.NetBearType.BEARER_ETHERNET
          ]
        }
      })
      this.netConnection.on('netAvailable', (netHandle: connection.NetHandle) => {
        this.onPhysicalNetAvailable(netHandle.netId)
      })
      this.netConnection.on('netLost', (netHandle: connection.NetHandle) => {
        if (netHandle.netId === this.currentNetId) {
          this.lostSinceLast = true
          Logger.info(`physical net lost netId=${netHandle.netId}`, this.options.logTarget)
        }
      })
      this.netConnection.register((error: BusinessError) => {
        if (error) {
          Logger.error(`net watchdog register failed: ${error.code} ${error.message}`, this.options.logTarget)
        }
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
    if (this.debounceTimer >= 0) {
      clearTimeout(this.debounceTimer)
      this.debounceTimer = -1
    }
    try {
      this.netConnection?.unregister((_error: BusinessError) => {
      })
    } catch (_) {
    }
    this.netConnection = undefined
    this.baselineSet = false
    this.currentNetId = -1
    this.lostSinceLast = false
  }

  private onPhysicalNetAvailable(netId: number): void {
    if (!this.started) {
      return
    }
    if (!this.baselineSet) {
      // 启动时的首个物理网络：仅作为基线，不触发重启
      this.baselineSet = true
      this.currentNetId = netId
      Logger.info(`physical net baseline netId=${netId}`, this.options.logTarget)
      return
    }
    const switched = netId !== this.currentNetId || this.lostSinceLast
    this.currentNetId = netId
    this.lostSinceLast = false
    if (!switched) {
      return
    }
    Logger.info(`physical net switched to netId=${netId}`, this.options.logTarget)
    this.scheduleRestart()
  }

  private scheduleRestart(): void {
    if (this.debounceTimer >= 0) {
      clearTimeout(this.debounceTimer)
    }
    this.debounceTimer = setTimeout(() => {
      this.debounceTimer = -1
      this.performRestart()
    }, SWITCH_DEBOUNCE_MS)
  }

  private performRestart(): void {
    if (!this.started) {
      return
    }
    const now = Date.now()
    if (now - this.lastRestartAt < RESTART_COOLDOWN_MS) {
      Logger.info('net watchdog restart skipped (cooldown)', this.options.logTarget)
      return
    }
    const ids = this.options.getRunningIds()
    if (ids.length === 0) {
      return
    }
    this.lastRestartAt = now
    Logger.info(`net switched, soft-restarting instances: ${ids.join(',')}`, this.options.logTarget)
    const run = (): void => {
      try {
        this.options.restartInstances(ids)
      } catch (error) {
        Logger.error(`net watchdog restart error: ${JSON.stringify(error)}`, this.options.logTarget)
      }
    }
    if (this.options.beforeRestart) {
      try {
        this.options.beforeRestart(run)
      } catch (_) {
        run()
      }
    } else {
      run()
    }
  }
}
