import { Want } from '@kit.AbilityKit'
import { JSON } from '@kit.ArkTS'
import { VpnExtensionAbility } from '@kit.NetworkKit'
import { hilog } from '@kit.PerformanceAnalysisKit'
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
  NetworkRestartResult,
  softRestartStoredInstances,
  startStoredInstances,
  stopStoredInstances
} from '../services/runtime/NetworkChangeWatchdog'
import { startRuntimeStatsRecording, stopRuntimeStatsRecording } from '../services/runtime/RuntimeStatsService'
import { VpnExtensionKernelSocketService } from '../services/runtime/VpnExtensionKernelSocketService'
import { VpnExtensionSettingsRepository } from '../services/runtime/VpnExtensionSettingsRepository'
import { VpnExtensionTunService, VpnExtensionTunSettings } from '../services/tun/VpnExtensionTunService'

const VPN_LIFECYCLE_DOMAIN = 0x9527
const VPN_LIFECYCLE_TAG = 'ET_VPN_EXT'
const MAX_PROCESSED_COMMANDS = 64

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
  private runtimeState: VpnRuntimeStateName = 'idle'
  private runtimeStatusGeneration: number = 0
  private lifecycleGeneration: number = 0
  private destroyed: boolean = false
  private shutdownStarted: boolean = false
  private processInitialized: boolean = false
  private commandQueue: Promise<void> = Promise.resolve()
  private processedCommandResults: Map<string, VpnRuntimeCommandResultData> = new Map()
  private processedCommandOrder: string[] = []

  onCreate(want: Want): void {
    vpnLifecycleInfo(`onCreate enter parameters=${want.parameters !== undefined}`)
    this.lifecycleGeneration++
    this.destroyed = false
    this.shutdownStarted = false
    const parameters = want.parameters
    this.configRootDir = parameters?.['config_root_dir'] as string ?? this.context.filesDir
    this.socketFilesDir = parameters?.['socket_files_dir'] as string ?? this.context.filesDir
    const socketName = parameters?.['socket'] as string ?? VPN_EXTENSION_SOCKET_NAME

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

  private startLogForwarding(): void {
    if (this.timer !== undefined) {
      return
    }
    this.timer = setInterval(() => {
      this.bridgeServer.forwardLogs(easytier.drainLogLines())
    }, 500)
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
    return command.command === 'stop' || command.command === 'status'
  }

  private async processRuntimeCommand(command: VpnRuntimeCommandData): Promise<VpnRuntimeCommandResultData> {
    switch (command.command) {
      case 'start':
        return await this.startRuntime(command)
      case 'restart':
        return await this.restartRuntime(command)
      case 'stop':
        return await this.stopRuntime(command)
      default:
        return this.buildCommandResult(command, true)
    }
  }

  private async startRuntime(command: VpnRuntimeCommandData): Promise<VpnRuntimeCommandResultData> {
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
      const started = await startStoredInstances([command.instanceId])
      if (!started || this.destroyed || lifecycleGeneration !== this.lifecycleGeneration) {
        if (started) {
          await stopStoredInstances([command.instanceId])
        }
        throw new Error(started ? 'runtime_start_cancelled' : 'kernel_start_rejected')
      }
      startRuntimeStatsRecording(this.context.filesDir)
      this.kernelSocketService.connect(this.configRootDir + '/' + KERNEL_SOCKET_NAME)
      this.transitionTo('running')
      return this.buildCommandResult(command, true, undefined, false, true)
    } catch (error) {
      const err = error as Error
      await this.tunService.destroy()
      this.tunService = undefined
      this.currentInstanceId = ''
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
      result = await softRestartStoredInstances([command.instanceId], () => {
        return !this.destroyed && lifecycleGeneration === this.lifecycleGeneration
      })
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
      this.bridgeServer.publishContinuationState(false)
    }
    this.transitionTo('error', result.cancelled ? 'runtime_restart_cancelled' : 'kernel_restart_failed')
    return this.buildCommandResult(command, false,
      result.cancelled ? 'runtime_restart_cancelled' : 'kernel_restart_failed', result.stopped, false)
  }

  private async stopRuntime(command: VpnRuntimeCommandData): Promise<VpnRuntimeCommandResultData> {
    if (this.currentInstanceId.length === 0) {
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
      this.bridgeServer.publishContinuationState(false)
    }
    this.transitionTo('idle')
    return this.buildCommandResult(command, true, undefined, true, false)
  }

  private beginKernelGeneration(): void {
    this.kernelSocketService.close()
    this.bridgeServer.beginRuntimeGeneration()
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
    return {
      requestId: command.requestId,
      generation: command.generation,
      command: command.command,
      instanceId: command.instanceId.length > 0 ? command.instanceId : this.currentInstanceId,
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
    if (this.timer !== undefined) {
      clearInterval(this.timer)
      this.timer = undefined
    }
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
      this.bridgeServer.publishContinuationState(false)
      this.bridgeServer.close()
    }
  }
}
