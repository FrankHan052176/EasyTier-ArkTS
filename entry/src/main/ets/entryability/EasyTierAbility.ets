import { Want } from '@kit.AbilityKit'
import { JSON } from '@kit.ArkTS'
import { VpnExtensionAbility } from '@kit.NetworkKit'
import { hilog } from '@kit.PerformanceAnalysisKit'
import { fileIo } from '@kit.CoreFileKit'
import easytier from 'easytier-ohrs'
import { ConfigJson } from '../config/schema/SchemaConfig'
import {
  KERNEL_SOCKET_NAME,
  VpnRuntimeCommandData,
  VpnRuntimeCommandResultData,
  VpnRuntimeStateName,
  VpnRuntimeStatusData
} from '../infrastructure/bridge/kernel/KernelBridgeTypes'
import { VpnBridgeServer } from '../infrastructure/bridge/kernel/VpnBridgeServer'
import { Logger } from '../shared/logging/Logger'
import { VPN_EXTENSION_SOCKET_NAME } from '../services/runtime/AbilityRuntimePolicy'
import {
  NetworkChangeWatchdog,
  NetworkRestartResult,
  softRestartOneShotInstance,
  softRestartStoredInstances,
  startOneShotInstance,
  startStoredInstances,
  stopStoredInstances
} from '../services/runtime/NetworkChangeWatchdog'
import { RuntimeHostLease } from '../services/runtime/RuntimeHostLease'
import { startRuntimeStatsRecording, stopRuntimeStatsRecording } from '../services/runtime/RuntimeStatsService'
import { VpnExtensionKernelSocketService } from '../services/runtime/VpnExtensionKernelSocketService'
import { VpnExtensionSettingsRepository } from '../services/runtime/VpnExtensionSettingsRepository'
import { VpnExtensionTunService, VpnExtensionTunSettings } from '../services/tun/VpnExtensionTunService'

const VPN_LIFECYCLE_DOMAIN = 0x9527
const VPN_LIFECYCLE_TAG = 'ET_VPN_EXT'
const MAX_PROCESSED_COMMANDS = 64

/**
 * Core（nearby_management.rs MANAGEMENT_SOCKET_FILE_NAME）在 config_root_dir 下
 * 绑定的管理宿主 socket。stop 只 take/drop，unlink 在 Drop 中异步完成，
 * 因此只有观察到路径消失才能认定本进程已真正释放宿主。
 *
 * 路径本身不能证明持有者是否还活着（崩溃会残留路径），所以"谁是宿主"由
 * RuntimeHostLease 的进程间文件锁证明：锁在手里才能调 native start。
 */
const NEARBY_MANAGEMENT_SOCKET_NAME = 'easytier-nearby-management.sock'
const NEARBY_HOST_RELEASE_POLL_MS = 25
const NEARBY_HOST_RELEASE_TIMEOUT_MS = 5000

function delay(milliseconds: number): Promise<void> {
  return new Promise<void>((resolve) => {
    setTimeout(resolve, milliseconds)
  })
}

interface NearbyHostCommandData {
  requestId: string
  operation: string
  instanceId: string
  configJson?: string
}

function vpnLifecycleInfo(message: string): void {
  hilog.info(VPN_LIFECYCLE_DOMAIN, VPN_LIFECYCLE_TAG, '%{public}s', message)
}

function vpnLifecycleError(message: string): void {
  hilog.error(VPN_LIFECYCLE_DOMAIN, VPN_LIFECYCLE_TAG, '%{public}s', message)
}

vpnLifecycleInfo('module loaded')

export default class EasyTierAbility extends VpnExtensionAbility {
  private bridgeServer: VpnBridgeServer = new VpnBridgeServer('EasyTierAbility',
    (command: VpnRuntimeCommandData) => {
      this.handleRuntimeCommand(command)
    })
  private kernelSocketService: VpnExtensionKernelSocketService = new VpnExtensionKernelSocketService({
    logTarget: 'EasyTierAbility',
    onTunRequest: (payload, trigger: string) => {
      this.tunService?.handleKernelTunRequest(payload, trigger)
    },
    broadcastRaw: (rawMessage: string) => {
      this.bridgeServer.broadcastRaw(rawMessage)
    }
  })
  private tunService: VpnExtensionTunService | undefined = undefined
  private timer: number | undefined = undefined
  private configRootDir: string = ''
  private socketFilesDir: string = ''
  private currentInstanceId: string = ''
  private currentOneShotConfigJson: string = ''
  private currentOneShotRequestId: string = ''
  private runtimeState: VpnRuntimeStateName = 'idle'
  private runtimeStatusGeneration: number = 0
  private lifecycleGeneration: number = 0
  private destroyed: boolean = false
  private shutdownStarted: boolean = false
  private processInitialized: boolean = false
  private commandQueue: Promise<void> = Promise.resolve()
  private processedCommandResults: Map<string, VpnRuntimeCommandResultData> = new Map()
  private processedCommandOrder: string[] = []
  /**
   * 本进程是否持有 Core nearby 管理宿主。shutdown 成功后置 false，
   * finishShutdown 只在仍持有时释放，避免二次 unlink 新的宿主 socket。
   */
  private nearbyHostOwned: boolean = false
  /**
   * 停过宿主但尚未观察到 socket 路径消失；超时后保持 true，
   * 后续重新持有宿主前仍必须继续等待，不允许绕过。
   */
  private nearbyHostReleasePending: boolean = false
  /**
   * nearby 宿主的进程间所有权凭证。configRootDir 确定后建立，覆盖整个生命周期：
   * native 宿主被证实释放（socket 路径消失）之前绝不解锁。
   */
  private nearbyHostLease: RuntimeHostLease | undefined = undefined
  private networkWatchdog: NetworkChangeWatchdog | undefined = undefined
  private watchdogRestartSequence: number = 0

  onCreate(want: Want): void {
    vpnLifecycleInfo(`onCreate enter parameters=${want.parameters !== undefined}`)
    this.lifecycleGeneration++
    this.destroyed = false
    this.shutdownStarted = false
    const parameters = want.parameters
    this.configRootDir = parameters?.['config_root_dir'] as string ?? this.context.filesDir
    this.socketFilesDir = parameters?.['socket_files_dir'] as string ?? this.context.filesDir
    const socketName = parameters?.['socket'] as string ?? VPN_EXTENSION_SOCKET_NAME
    // The lease covers the bridge as well as Core, including initialization failures.
    this.nearbyHostLease = new RuntimeHostLease(this.configRootDir)
    if (!this.tryAcquireNearbyHostLease()) {
      this.transitionTo('error', 'runtime_host_lease_unavailable')
      return
    }

    try {
      this.bridgeServer.start(this.socketFilesDir, socketName)
      vpnLifecycleInfo(`bridge server start requested socket=${socketName}`)
    } catch (error) {
      const err = error as Error
      vpnLifecycleError(`bridge server start failed: ${err.message}`)
      this.transitionTo('error', 'bridge_server_start_failed')
      return
    }

    this.processInitialized = this.initializeProcess()
    if (this.processInitialized) {
      this.transitionTo('idle')
      this.startNetworkWatchdog()
    } else {
      this.transitionTo('error', 'extension_process_initialization_failed')
    }
  }

  private initializeProcess(): boolean {
    if (this.configRootDir.length === 0 || this.socketFilesDir.length === 0) {
      vpnLifecycleError('extension bootstrap paths are empty')
      return false
    }
    try {
      const settings = VpnExtensionSettingsRepository.load(this.context)
      easytier.initLogManager(this.socketFilesDir, 'vpn')
      easytier.configureLogManager(settings.coreLog, settings.debugLog)
      if (!easytier.initConfigStore(this.configRootDir)) {
        vpnLifecycleError(`initConfigStore failed root=${this.configRootDir}`)
        return false
      }
      if (!easytier.startNearbyManagementHost()) {
        vpnLifecycleError('nearby management host failed to start')
        return false
      }
      this.nearbyHostOwned = true
      easytier.initPanicHook()
      if (settings.coreLog) {
        easytier.initTracingSubscriber()
      }
      this.startLogForwarding()
      vpnLifecycleInfo(`extension process initialized configRoot=${this.configRootDir}`)
      return true
    } catch (error) {
      const err = error as Error
      vpnLifecycleError(`extension process initialization failed: ${err.message}`)
      return false
    }
  }

  private tryAcquireNearbyHostLease(): boolean {
    const lease = this.nearbyHostLease
    if (lease === undefined) {
      return false
    }
    return lease.tryAcquire()
  }


  private startLogForwarding(): void {
    if (this.timer !== undefined) {
      return
    }
    this.timer = setInterval(() => {
      this.bridgeServer.forwardLogs(easytier.drainLogLines())
      if (this.nearbyHostOwned) {
        this.drainNearbyHostCommands()
      }
    }, 500)
  }

  /**
   * 内核宿主就在本进程，切网软重启必须在这里完成：网络变化看护器随扩展
   * 生命周期存在，不依赖 UI 进程；重启事务排入既有 commandQueue，
   * 与 IPC/近场命令严格串行。
   */
  private startNetworkWatchdog(): void {
    if (this.networkWatchdog) {
      return
    }
    this.networkWatchdog = new NetworkChangeWatchdog({
      logTarget: 'EasyTierAbility',
      getRunningIds: () => {
        if (this.currentInstanceId.length === 0 || this.runtimeState !== 'running') {
          return []
        }
        return [this.currentInstanceId]
      },
      restartInstances: (ids: string[]): Promise<NetworkRestartResult> => {
        return this.enqueueWatchdogRestart(ids)
      }
    })
    this.networkWatchdog.start()
  }

  private enqueueWatchdogRestart(ids: string[]): Promise<NetworkRestartResult> {
    const instanceId = this.currentInstanceId
    if (this.destroyed || instanceId.length === 0 || ids.indexOf(instanceId) < 0) {
      return Promise.resolve(this.buildWatchdogRestartResult(false, false, true))
    }
    const command: VpnRuntimeCommandData = {
      requestId: `net-watchdog-${++this.watchdogRestartSequence}`,
      generation: ++this.runtimeStatusGeneration,
      command: 'restart',
      instanceId
    }
    const operation = this.commandQueue.catch(() => {}).then(async () => {
      if (this.destroyed || this.currentInstanceId !== instanceId) {
        return this.buildWatchdogRestartResult(false, false, true)
      }
      return this.toWatchdogRestartResult(await this.processRuntimeCommand(command))
    })
    this.commandQueue = operation.then(() => {}, (error: Error) => {
      Logger.error(`network watchdog restart failed: ${error.message}`, 'EasyTierAbility')
    })
    return operation
  }

  private buildWatchdogRestartResult(stopped: boolean, started: boolean, cancelled: boolean): NetworkRestartResult {
    return {
      stopped,
      started,
      cancelled
    }
  }

  private toWatchdogRestartResult(result: VpnRuntimeCommandResultData): NetworkRestartResult {
    return this.buildWatchdogRestartResult(result.stopped === true, result.started === true,
      !result.success && result.started !== true)
  }

  private drainNearbyHostCommands(): void {
    const commands = easytier.drainNearbyHostCommands() as NearbyHostCommandData[]
    for (const command of commands) {
      const operation = this.commandQueue.catch(() => {}).then(async () => {
        const result = await this.processNearbyHostCommand(command)
        const completed = easytier.completeNearbyHostCommand(command.requestId, result.success, result.error)
        if (!completed && command.operation === 'start_once' && result.success &&
          this.currentOneShotRequestId === command.requestId) {
          await this.rollbackUnacknowledgedNearbyStart(command)
        }
      })
      this.commandQueue = operation.catch((error: Error) => {
        Logger.error(`nearby host command failed request=${command.requestId}: ${error.message}`, 'EasyTierAbility')
        easytier.completeNearbyHostCommand(command.requestId, false, error.message)
      })
    }
  }

  private async processNearbyHostCommand(command: NearbyHostCommandData): Promise<VpnRuntimeCommandResultData> {
    const runtimeCommand: VpnRuntimeCommandData = {
      requestId: command.requestId,
      generation: ++this.runtimeStatusGeneration,
      command: command.operation === 'stop' ? 'stop' : 'start',
      instanceId: command.instanceId
    }
    if (command.operation === 'stop') {
      return await this.stopRuntime(runtimeCommand)
    }
    if (command.operation !== 'start_once' || !command.configJson) {
      return this.buildCommandResult(runtimeCommand, false, 'nearby_host_command_invalid')
    }
    let config: ConfigJson
    try {
      config = JSON.parse(command.configJson) as ConfigJson
    } catch (_) {
      return this.buildCommandResult(runtimeCommand, false, 'one_shot_config_invalid')
    }
    if (config.instance_id !== command.instanceId) {
      return this.buildCommandResult(runtimeCommand, false, 'one_shot_config_instance_mismatch')
    }
    const normalizedConfig = JSON.stringify(config)
    return await this.startRuntimeWithConfig(runtimeCommand, config, async () => {
      return await startOneShotInstance(normalizedConfig)
    }, normalizedConfig, command.requestId)
  }

  private async rollbackUnacknowledgedNearbyStart(command: NearbyHostCommandData): Promise<void> {
    if (this.currentOneShotRequestId !== command.requestId || this.currentInstanceId !== command.instanceId) {
      return
    }
    Logger.warn(`rolling back unacknowledged nearby start request=${command.requestId}`, 'EasyTierAbility')
    const rollbackCommand: VpnRuntimeCommandData = {
      requestId: command.requestId,
      generation: ++this.runtimeStatusGeneration,
      command: 'stop',
      instanceId: command.instanceId
    }
    try {
      const result = await this.stopRuntime(rollbackCommand)
      if (!result.success) {
        Logger.error(`nearby start rollback failed request=${command.requestId}: ${result.error ?? 'unknown'}`,
          'EasyTierAbility')
      }
    } catch (error) {
      const err = error as Error
      Logger.error(`nearby start rollback threw request=${command.requestId}: ${err.message}`, 'EasyTierAbility')
    }
  }

  private handleRuntimeCommand(command: VpnRuntimeCommandData): void {
    const cached = this.processedCommandResults.get(command.requestId)
    if (cached !== undefined) {
      this.bridgeServer.publishRuntimeCommandResult(cached)
      return
    }
    if (!this.isValidCommand(command)) {
      this.publishCommandResult(this.buildCommandResult(command, false, 'runtime_command_invalid'))
      return
    }
    const operation = this.commandQueue.catch(() => {}).then(async () => {
      const cachedResult = this.processedCommandResults.get(command.requestId)
      if (cachedResult !== undefined) {
        // IPC 重连会重发同一 requestId：首个命令还在 await 时重复入队，
        // 这里在真正执行前再查一次缓存并原样重放，绝不重复执行。
        this.publishCommandResult(cachedResult)
        return
      }
      if (this.destroyed) {
        this.publishCommandResult(this.buildCommandResult(command, false, 'vpn_extension_destroyed'))
        return
      }
      const result = await this.processRuntimeCommand(command)
      this.publishCommandResult(result)
    })
    this.commandQueue = operation.catch((error: Error) => {
      Logger.error(`runtime command failed request=${command.requestId}: ${error.message}`, 'EasyTierAbility')
      this.publishCommandResult(this.buildCommandResult(command, false, error.message))
    })
  }

  private isValidCommand(command: VpnRuntimeCommandData): boolean {
    if (command.requestId.length === 0 || command.generation <= 0) {
      return false
    }
    if (command.command === 'start' || command.command === 'restart') {
      return command.instanceId.length > 0
    }
    return command.command === 'stop' || command.command === 'status' || command.command === 'shutdown'
  }

  private async processRuntimeCommand(command: VpnRuntimeCommandData): Promise<VpnRuntimeCommandResultData> {
    switch (command.command) {
      case 'start':
        return await this.startRuntime(command)
      case 'restart':
        return await this.restartRuntime(command)
      case 'stop':
        return await this.stopRuntime(command)
      case 'shutdown':
        return await this.shutdownRuntime(command)
      default:
        return this.buildCommandResult(command, true)
    }
  }

  /**
   * 显式停止（用户停止运行方案）：先停掉实际运行实例，沿用 stop 的
   * “拒绝即保留运行态”语义；成功后立即交还 nearby 宿主并回 ACK。
   * 桥在此处保持开启，确保 ACK 能送达发起方。
   */
  private async shutdownRuntime(command: VpnRuntimeCommandData): Promise<VpnRuntimeCommandResultData> {
    const stopCommand: VpnRuntimeCommandData = {
      requestId: command.requestId,
      generation: command.generation,
      command: 'stop',
      instanceId: this.currentInstanceId
    }
    const stopResult = await this.stopRuntime(stopCommand)
    if (!stopResult.success) {
      return this.buildCommandResult(command, false, stopResult.error, stopResult.stopped, stopResult.started)
    }
    vpnLifecycleInfo('runtime shutdown acknowledged; releasing nearby management host')
    this.stopOwnedNearbyHost()
    if (!await this.awaitNearbyHostRelease()) {
      return this.buildCommandResult(command, false, 'nearby_host_release_unconfirmed', true, false)
    }
    return this.buildCommandResult(command, true, undefined, true, false)
  }

  /**
   * shutdown 之后宿主交给下一任持有者（通常是重新接管的主进程）；
   * 只有本进程真正持有过才释放，避免二次 unlink 新宿主的 socket。
   *
   * 宿主锁不在这里释放：要等 socket 路径真正消失（finishShutdown）才 release，
   * 否则主进程的 lease 探测会把仍在清理宿主的扩展当成已退出。
   */
  private stopOwnedNearbyHost(): void {
    if (!this.nearbyHostOwned) {
      return
    }
    this.nearbyHostOwned = false
    this.nearbyHostReleasePending = true
    if (!easytier.stopNearbyManagementHost()) {
      vpnLifecycleError('nearby management host stop was rejected')
    }
  }

  private nearbyManagementSocketPath(): string {
    return this.configRootDir + '/' + NEARBY_MANAGEMENT_SOCKET_NAME
  }

  private isNearbyManagementSocketPresent(): boolean {
    try {
      return fileIo.accessSync(this.nearbyManagementSocketPath())
    } catch (error) {
      // 探针失败的保守结论是“仍在”：宁可等待超时，也不误判为已释放。
      vpnLifecycleError(`nearby management socket probe failed: ${JSON.stringify(error)}`)
      return true
    }
  }

  /**
   * 有界等待本进程停掉的宿主真正释放（Core Drop 才 unlink）。
   * 只有观察到路径消失才清 releasePending，超时保持 pending。
   */
  private async awaitNearbyHostRelease(): Promise<boolean> {
    if (!this.nearbyHostReleasePending) {
      return true
    }
    const socketPath = this.nearbyManagementSocketPath()
    const deadline = Date.now() + NEARBY_HOST_RELEASE_TIMEOUT_MS
    while (Date.now() < deadline) {
      if (!this.isNearbyManagementSocketPresent()) {
        this.nearbyHostReleasePending = false
        vpnLifecycleInfo('nearby management host released for extension handover')
        return true
      }
      await delay(NEARBY_HOST_RELEASE_POLL_MS)
    }
    vpnLifecycleError(`nearby management socket still present after release timeout: ${socketPath}`)
    return false
  }

  /**
   * runtime start 前确保持有宿主：先幂等地重拿自己的 lease（别的进程持有就拒绝，
   * 绝不启动第二个宿主），再等自家上一任宿主的 socket 真正消失，最后才 native start。
   * 残留 socket 路径本身不是拒绝理由——锁已经证明没有别的活宿主，native 会清理它。
   */
  private async ensureNearbyHostOwned(): Promise<void> {
    if (this.nearbyHostOwned) {
      return
    }
    if (!this.tryAcquireNearbyHostLease()) {
      throw new Error('nearby_host_lease_unavailable')
    }
    if (!await this.awaitNearbyHostRelease()) {
      throw new Error('nearby_host_release_unconfirmed')
    }
    if (easytier.startNearbyManagementHost()) {
      this.nearbyHostOwned = true
      vpnLifecycleInfo('nearby management host reclaimed for extension runtime')
      return
    }
    throw new Error('nearby_host_start_failed')
  }

  private async startRuntime(command: VpnRuntimeCommandData): Promise<VpnRuntimeCommandResultData> {
    const oneShotConfigJson = command.configJson ?? ''
    if (oneShotConfigJson.length > 0) {
      // 带 configJson 的 start 是不落库的一次性实例：只按命令载荷运行，
      // 并保留配置以便切网软重启时按同一份配置拉起。
      let oneShotConfig: ConfigJson
      try {
        oneShotConfig = JSON.parse(oneShotConfigJson) as ConfigJson
      } catch (_) {
        return this.buildCommandResult(command, false, 'one_shot_config_invalid')
      }
      if (oneShotConfig.instance_id !== command.instanceId) {
        return this.buildCommandResult(command, false, 'one_shot_config_instance_mismatch')
      }
      const normalizedConfig = JSON.stringify(oneShotConfig)
      return await this.startRuntimeWithConfig(command, oneShotConfig, async () => {
        return await startOneShotInstance(normalizedConfig)
      }, normalizedConfig)
    }
    const rawConfig = easytier.getConfig(command.instanceId)
    if (!rawConfig) {
      return this.buildCommandResult(command, false, 'stored_config_not_found')
    }
    let config: ConfigJson
    try {
      config = JSON.parse(rawConfig) as ConfigJson
    } catch (_) {
      return this.buildCommandResult(command, false, 'stored_config_invalid')
    }
    const configInstanceId = config.instance_id as string | undefined
    if (configInstanceId && configInstanceId !== command.instanceId) {
      return this.buildCommandResult(command, false, 'stored_config_instance_mismatch')
    }
    return await this.startRuntimeWithConfig(command, config, async () => {
      return await startStoredInstances([command.instanceId])
    })
  }

  private async startRuntimeWithConfig(command: VpnRuntimeCommandData, config: ConfigJson,
    startKernel: () => Promise<boolean>, oneShotConfigJson: string = '',
    oneShotRequestId: string = ''): Promise<VpnRuntimeCommandResultData> {
    if (!this.processInitialized) {
      return this.buildCommandResult(command, false, 'extension_process_not_initialized')
    }
    if (this.runtimeState === 'running' && this.currentInstanceId === command.instanceId) {
      return this.buildCommandResult(command, true, undefined, false, true)
    }
    if (this.currentInstanceId.length > 0 || this.runtimeState === 'starting' || this.runtimeState === 'restarting' ||
      this.runtimeState === 'stopping') {
      return this.buildCommandResult(command, false, 'another_runtime_is_active')
    }
    this.currentOneShotConfigJson = ''
    this.currentOneShotRequestId = ''
    const settings = VpnExtensionSettingsRepository.load(this.context)
    easytier.configureLogManager(settings.coreLog, settings.debugLog)
    const tunSettings: VpnExtensionTunSettings = {
      whiteList: settings.whiteList,
      blackList: settings.blackList,
      dns: settings.dns,
      dev: settings.dev,
      forceGlobal: settings.forceGlobal
    }
    this.currentInstanceId = command.instanceId
    this.tunService = new VpnExtensionTunService({
      context: this.context,
      logTarget: 'EasyTierAbility',
      instanceId: command.instanceId,
      config,
      settings: tunSettings,
      publishContinuationState: (active: boolean) => {
        this.bridgeServer.publishContinuationState(active)
      },
      setTunFd: (instanceId: string, fd: number) => {
        return easytier.setTunFd(instanceId, fd)
      },
      onProtectionFatal: (error: Error) => {
        this.handleSocketProtectionFatal(error)
      }
    })
    this.transitionTo('starting')
    this.beginKernelGeneration()
    const lifecycleGeneration = this.lifecycleGeneration
    try {
      await this.tunService.prepareProtection()
      if (this.destroyed || lifecycleGeneration !== this.lifecycleGeneration) {
        throw new Error('runtime_start_cancelled')
      }
      await this.ensureNearbyHostOwned()
      const started = await startKernel()
      if (!started || this.destroyed || lifecycleGeneration !== this.lifecycleGeneration) {
        if (started) {
          await stopStoredInstances([command.instanceId])
        }
        throw new Error(started ? 'runtime_start_cancelled' : 'kernel_start_rejected')
      }
      this.currentOneShotConfigJson = oneShotConfigJson
      this.currentOneShotRequestId = oneShotRequestId
      startRuntimeStatsRecording(this.context.filesDir)
      this.kernelSocketService.connect(this.configRootDir + '/' + KERNEL_SOCKET_NAME)
      this.transitionTo('running')
      return this.buildCommandResult(command, true, undefined, false, true)
    } catch (error) {
      const err = error as Error
      await this.tunService.destroy()
      this.tunService = undefined
      this.currentInstanceId = ''
      this.currentOneShotConfigJson = ''
      this.currentOneShotRequestId = ''
      stopRuntimeStatsRecording()
      this.transitionTo('error', err.message)
      return this.buildCommandResult(command, false, err.message, false, false)
    }
  }

  private async restartRuntime(command: VpnRuntimeCommandData): Promise<VpnRuntimeCommandResultData> {
    if (this.runtimeState !== 'running' || this.currentInstanceId !== command.instanceId || !this.tunService) {
      return this.buildCommandResult(command, false, 'runtime_not_running')
    }
    const tunService = this.tunService
    const lifecycleGeneration = this.lifecycleGeneration
    if (!await tunService.beginKernelRestart()) {
      return this.buildCommandResult(command, false, 'tun_transaction_busy')
    }
    this.transitionTo('restarting')
    this.beginKernelGeneration()
    let result: NetworkRestartResult
    try {
      const shouldStart = () => !this.destroyed && lifecycleGeneration === this.lifecycleGeneration
      result = this.currentOneShotConfigJson.length > 0 ?
        await softRestartOneShotInstance(command.instanceId, this.currentOneShotConfigJson, shouldStart) :
        await softRestartStoredInstances([command.instanceId], shouldStart)
    } catch (error) {
      await tunService.completeKernelRestart(false)
      const err = error as Error
      this.transitionTo('error', err.message)
      return this.buildCommandResult(command, false, err.message)
    }
    const lifecycleCurrent = !this.destroyed && lifecycleGeneration === this.lifecycleGeneration
    if (!result.stopped && lifecycleCurrent) {
      this.kernelSocketService.connect(this.configRootDir + '/' + KERNEL_SOCKET_NAME)
      await tunService.completeKernelRestart(true)
      this.transitionTo('running', 'kernel_stop_rejected')
      return this.buildCommandResult(command, false, 'kernel_stop_rejected', false, true)
    }
    const running = result.started && lifecycleCurrent
    if (running) {
      this.kernelSocketService.connect(this.configRootDir + '/' + KERNEL_SOCKET_NAME)
    }
    await tunService.completeKernelRestart(running)
    if (!lifecycleCurrent && result.started) {
      await stopStoredInstances([command.instanceId])
    }
    if (running) {
      this.transitionTo('running')
      return this.buildCommandResult(command, true, undefined, result.stopped, true)
    }
    if (result.stopped && lifecycleCurrent) {
      await tunService.destroy()
      this.tunService = undefined
      this.currentInstanceId = ''
      this.currentOneShotConfigJson = ''
      this.currentOneShotRequestId = ''
      this.bridgeServer.publishContinuationState(false)
    }
    this.transitionTo('error', result.cancelled ? 'runtime_restart_cancelled' : 'kernel_restart_failed')
    return this.buildCommandResult(command, false,
      result.cancelled ? 'runtime_restart_cancelled' : 'kernel_restart_failed', result.stopped, false)
  }

  private async stopRuntime(command: VpnRuntimeCommandData): Promise<VpnRuntimeCommandResultData> {
    if (this.currentInstanceId.length === 0) {
      this.currentOneShotConfigJson = ''
      this.currentOneShotRequestId = ''
      this.transitionTo('idle')
      return this.buildCommandResult(command, true, undefined, true, false)
    }
    if (command.instanceId.length > 0 && command.instanceId !== this.currentInstanceId) {
      return this.buildCommandResult(command, false, 'runtime_instance_mismatch')
    }
    const stoppingInstanceId = this.currentInstanceId
    this.transitionTo('stopping')
    this.kernelSocketService.close()
    this.bridgeServer.beginRuntimeGeneration()
    stopRuntimeStatsRecording()
    const stopped = await stopStoredInstances([stoppingInstanceId])
    if (!stopped) {
      startRuntimeStatsRecording(this.context.filesDir)
      this.kernelSocketService.connect(this.configRootDir + '/' + KERNEL_SOCKET_NAME)
      this.transitionTo('running', 'kernel_stop_rejected')
      return this.buildCommandResult(command, false, 'kernel_stop_rejected', false, true)
    }
    try {
      await this.tunService?.destroy()
    } finally {
      this.tunService = undefined
      this.currentInstanceId = ''
      this.currentOneShotConfigJson = ''
      this.currentOneShotRequestId = ''
      this.bridgeServer.publishContinuationState(false)
    }
    this.transitionTo('idle')
    return this.buildCommandResult(command, true, undefined, true, false)
  }

  private beginKernelGeneration(): void {
    this.kernelSocketService.close()
    this.bridgeServer.beginRuntimeGeneration()
  }

  private handleSocketProtectionFatal(error: Error): void {
    const failedTunService = this.tunService
    if (!failedTunService) {
      return
    }
    const fatalError = `socket_protection_failed:${error.message}`
    const operation = this.commandQueue.catch(() => {}).then(async () => {
      if (this.tunService !== failedTunService) {
        return
      }
      const failedInstanceId = this.currentInstanceId
      this.transitionTo('stopping', fatalError)
      this.kernelSocketService.close()
      this.bridgeServer.beginRuntimeGeneration()
      stopRuntimeStatsRecording()
      let stopError = ''
      try {
        if (failedInstanceId.length > 0 && !await stopStoredInstances([failedInstanceId])) {
          stopError = ':kernel_stop_rejected'
        }
      } catch (error) {
        stopError = `:${(error as Error).message}`
      }
      try {
        await failedTunService.destroy()
      } finally {
        if (this.tunService === failedTunService) {
          this.tunService = undefined
          this.currentInstanceId = ''
          this.currentOneShotConfigJson = ''
          this.currentOneShotRequestId = ''
          this.bridgeServer.publishContinuationState(false)
        }
      }
      this.transitionTo('error', fatalError + stopError)
    })
    this.commandQueue = operation.catch((fatalStopError: Error) => {
      Logger.error(`socket protection fail-stop failed: ${fatalStopError.message}`, 'EasyTierAbility')
      this.transitionTo('error', `${fatalError}:${fatalStopError.message}`)
    })
  }

  private transitionTo(state: VpnRuntimeStateName, error?: string): void {
    this.runtimeState = state
    const status: VpnRuntimeStatusData = {
      generation: ++this.runtimeStatusGeneration,
      instanceId: this.currentInstanceId,
      state,
      error
    }
    this.bridgeServer.publishRuntimeStatus(status)
  }

  private buildCommandResult(command: VpnRuntimeCommandData, success: boolean, error?: string,
    stopped?: boolean, started?: boolean): VpnRuntimeCommandResultData {
    // status 与 shutdown 必须回报本进程实际处理的实例，而不是命令携带的旧值。
    const reportCurrentInstance = command.command === 'status' || command.command === 'shutdown'
    return {
      requestId: command.requestId,
      generation: command.generation,
      // 结果产生时的本进程状态代次：调用方用它区分"重放/迟到的旧 ACK"与重连后的新状态。
      statusGeneration: this.runtimeStatusGeneration,
      command: command.command,
      instanceId: !reportCurrentInstance && command.instanceId.length > 0 ? command.instanceId : this.currentInstanceId,
      success,
      state: this.runtimeState,
      stopped,
      started,
      error
    }
  }

  private publishCommandResult(result: VpnRuntimeCommandResultData): void {
    if (!this.processedCommandResults.has(result.requestId)) {
      this.processedCommandResults.set(result.requestId, result)
      this.processedCommandOrder.push(result.requestId)
      while (this.processedCommandOrder.length > MAX_PROCESSED_COMMANDS) {
        const expiredRequestId = this.processedCommandOrder.shift()
        if (expiredRequestId !== undefined) {
          this.processedCommandResults.delete(expiredRequestId)
        }
      }
    }
    this.bridgeServer.publishRuntimeCommandResult(result)
  }

  onDestroy(): void {
    vpnLifecycleInfo('onDestroy enter')
    this.destroyed = true
    this.lifecycleGeneration++
    this.networkWatchdog?.stop()
    this.networkWatchdog = undefined
    if (this.timer !== undefined) {
      clearInterval(this.timer)
      this.timer = undefined
    }
    // 宿主锁的释放必须异步等到 finishShutdown 里 native 宿主真正释放、
    // 桥也关闭之后：既不能在 stop 之后立刻解锁，也不能把锁永远挂在已停的宿主上。
    const shutdown = this.commandQueue.catch(() => {}).then(async () => {
      await this.finishShutdown()
    })
    this.commandQueue = shutdown.catch((error: Error) => {
      Logger.error(`extension shutdown failed: ${error.message}`, 'EasyTierAbility')
    })
  }

  private async finishShutdown(): Promise<void> {
    if (this.shutdownStarted) {
      return
    }
    this.shutdownStarted = true
    this.kernelSocketService.close()
    stopRuntimeStatsRecording()
    if (this.currentInstanceId.length > 0) {
      await stopStoredInstances([this.currentInstanceId])
    }
    try {
      await this.tunService?.destroy()
    } finally {
      this.tunService = undefined
      this.currentInstanceId = ''
      this.currentOneShotConfigJson = ''
      this.currentOneShotRequestId = ''
      this.bridgeServer.publishContinuationState(false)
      this.stopOwnedNearbyHost()
      // 先等 nearby 宿主真正释放，再关闭桥（桥 close 之后不再有可回报的通道）。
      if (!await this.awaitNearbyHostRelease()) {
        throw new Error('nearby_host_release_unconfirmed')
      }
      await this.bridgeServer.close()
      // 宿主已释放、桥已关闭：本进程不再是 nearby 宿主，交还宿主锁，让下一任
      // （重新接管的主进程）可以立即启动 native 宿主；解锁失败/未证实则保持持有。
      this.nearbyHostLease?.release()
    }
  }
}
