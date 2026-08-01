import { VpnExtensionAbility } from '@kit.NetworkKit';
import { hilog } from '@kit.PerformanceAnalysisKit'
import { Logger } from '../shared/logging/Logger';
import Want from '@ohos.app.ability.Want';
import easytier from 'easytier-ohrs';
import { JSON } from '@kit.ArkTS';
import { ConfigJson } from '../config/schema/SchemaConfig';
import {
  KERNEL_SOCKET_NAME,
  VpnRuntimeStartRequestData,
  VpnRuntimeStartResultData
} from '../infrastructure/bridge/kernel/KernelBridgeTypes'
import { VpnBridgeServer } from '../infrastructure/bridge/kernel/VpnBridgeServer'
import { startRuntimeStatsRecording, stopRuntimeStatsRecording } from '../services/runtime/RuntimeStatsService'
import { VpnExtensionKernelSocketService } from '../services/runtime/VpnExtensionKernelSocketService'
import { VpnExtensionTunService, VpnExtensionTunSettings } from '../services/tun/VpnExtensionTunService'
import { VPN_EXTENSION_SOCKET_NAME } from '../services/runtime/AbilityRuntimePolicy'
import {
  NetworkChangeWatchdog,
  NetworkRestartResult,
  softRestartWithConfig,
  stopStoredInstances
} from '../services/runtime/NetworkChangeWatchdog'

const VPN_LIFECYCLE_DOMAIN = 0x9527
const VPN_LIFECYCLE_TAG = 'ET_VPN_EXT'

function vpnLifecycleInfo(message: string): void {
  hilog.info(VPN_LIFECYCLE_DOMAIN, VPN_LIFECYCLE_TAG, '%{public}s', message)
}

function vpnLifecycleError(message: string): void {
  hilog.error(VPN_LIFECYCLE_DOMAIN, VPN_LIFECYCLE_TAG, '%{public}s', message)
}

vpnLifecycleInfo('module loaded')

export default class EasyTierAbility extends VpnExtensionAbility {
  private bridgeServer: VpnBridgeServer = new VpnBridgeServer('EasyTierAbility',
    (request: VpnRuntimeStartRequestData) => {
      this.handleRuntimeStartRequest(request)
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
  private networkWatchdog: NetworkChangeWatchdog | undefined = undefined
  timer: number | undefined
  config: ConfigJson | undefined
  instance_id: string = ""
  socketFilesDir: string = ''
  core_log: boolean = false
  debug_log: boolean = false
  private lifecycleGeneration: number = 0
  private destroyed: boolean = false
  private shutdownStarted: boolean = false
  private kernelRestartPromise: Promise<NetworkRestartResult> | undefined = undefined
  private runtimeInitializationStarted: boolean = false

  onCreate(want: Want): void {
    vpnLifecycleInfo(`onCreate enter parameters=${want.parameters !== undefined}`)
    const lifecycleGeneration = ++this.lifecycleGeneration
    this.destroyed = false
    this.shutdownStarted = false
    const parameters = want.parameters
    const callbackSocketFilesDir = parameters?.["socket_files_dir"] as string | undefined
    const callbackSocketName = parameters?.["socket"] as string | undefined
    this.socketFilesDir = callbackSocketFilesDir ?? this.context.filesDir

    try {
      // 首次授权在部分系统版本上会保留 parameters 对象却剥离应用自定义字段。
      // 因此同一次 Extension 实例先建立固定 IPC；授权完成后 UI 通过该连接
      // 下发完整运行参数，不做第二次 startVpnExtensionAbility。
      this.bridgeServer.start(this.socketFilesDir, callbackSocketName ?? VPN_EXTENSION_SOCKET_NAME)
      vpnLifecycleInfo('bridge server start requested')
    } catch (error) {
      const err = error as Error
      vpnLifecycleError(`bridge server start failed: ${err.message}`)
      return
    }

    const cfgParam = parameters?.["cfg"] as string | undefined
    if (!parameters || !cfgParam) {
      vpnLifecycleInfo('runtime parameters absent after authorization; waiting for IPC request')
      return
    }
    const directRequest: VpnRuntimeStartRequestData = {
      instanceId: parameters["instance_id"] as string ?? '',
      cfg: cfgParam,
      name: parameters["name"] as string ?? '',
      socketFilesDir: callbackSocketFilesDir ?? this.context.filesDir,
      vpnRoutes: parameters["vpn_routes"] as boolean ?? true,
      whiteList: parameters["white_list"] as boolean ?? false,
      blackList: parameters["black_list"] as string[] ?? [],
      dns: parameters["dns"] as string ?? '',
      dev: parameters["dev"] as boolean ?? false,
      forceGlobal: parameters["force_global"] as boolean ?? true,
      coreLog: parameters["core_log"] as boolean ?? (parameters["show_log"] as boolean ?? false),
      debugLog: parameters["debug_log"] as boolean ?? false
    }
    this.initializeRuntime(directRequest, lifecycleGeneration)
  }

  private handleRuntimeStartRequest(request: VpnRuntimeStartRequestData): void {
    vpnLifecycleInfo(`IPC runtime request received instance=${request.instanceId.length > 0}`)
    if (this.destroyed) {
      return
    }
    this.initializeRuntime(request, this.lifecycleGeneration)
  }

  private initializeRuntime(request: VpnRuntimeStartRequestData, lifecycleGeneration: number): void {
    if (this.runtimeInitializationStarted) {
      if (request.instanceId !== this.instance_id) {
        this.bridgeServer.publishRuntimeStartResult({
          instanceId: request.instanceId,
          started: false,
          error: 'vpn_extension_runtime_already_active'
        } as VpnRuntimeStartResultData)
      }
      return
    }
    if (request.instanceId.length === 0 || request.cfg.length === 0 || request.socketFilesDir.length === 0) {
      this.instance_id = request.instanceId
      this.publishInitializationFailure('vpn_extension_runtime_parameters_invalid')
      return
    }
    this.runtimeInitializationStarted = true
    this.instance_id = request.instanceId
    this.socketFilesDir = request.socketFilesDir
    this.core_log = request.coreLog
    this.debug_log = request.debugLog

    try {
      this.config = JSON.parse(request.cfg) as ConfigJson;
      const configInstanceId = this.config.instance_id as string | undefined
      if (configInstanceId && configInstanceId !== this.instance_id) {
        throw new Error('runtime instance id does not match config')
      }
      const tunSettings: VpnExtensionTunSettings = {
        whiteList: request.whiteList,
        blackList: request.blackList,
        dns: request.dns,
        dev: request.dev,
        forceGlobal: request.forceGlobal
      }
      this.tunService = new VpnExtensionTunService({
        context: this.context,
        logTarget: 'EasyTierAbility',
        instanceId: this.instance_id,
        config: this.config,
        settings: tunSettings,
        publishContinuationState: (active: boolean) => {
          this.bridgeServer.publishContinuationState(active)
        },
        setTunFd: (instanceId: string, fd: number) => {
          return easytier.setTunFd(instanceId, fd)
        }
      })

      vpnLifecycleInfo('initLogManager begin')
      easytier.initLogManager(this.socketFilesDir, 'vpn')
      easytier.configureLogManager(this.core_log, this.debug_log)
      vpnLifecycleInfo('initLogManager complete')
      Logger.debug("VpnExtAbi create", "EasyTierAbility")

      vpnLifecycleInfo('initConfigStore begin')
      if (!easytier.initConfigStore(this.socketFilesDir)) {
        Logger.error(`initConfigStore failed filesDir=${this.socketFilesDir}`, "EasyTierAbility")
        this.publishInitializationFailure('init_config_store_failed')
        return
      }
      vpnLifecycleInfo('initConfigStore complete')
      easytier.initPanicHook();

      if (this.core_log) {
        easytier.initTracingSubscriber();
      }
      vpnLifecycleInfo('prepareProtection begin')
      this.tunService.prepareProtection().catch((err: Error) => {
        Logger.error(`protectProcessNet failed before kernel start: ${JSON.stringify(err)}`, "EasyTierAbility")
      }).finally(() => {
        if (this.destroyed || lifecycleGeneration !== this.lifecycleGeneration) {
          return
        }
        vpnLifecycleInfo('prepareProtection complete; starting kernel')
        this.startCollecting();
        this.startKernel();
      })
    } catch (error) {
      const err = error as Error
      vpnLifecycleError(`runtime initialization failed: ${err.message}`)
      this.publishInitializationFailure('vpn_extension_initialization_failed')
    }
  }

  private publishInitializationFailure(error: string): void {
    this.bridgeServer.publishRuntimeStartResult({
      instanceId: this.instance_id,
      started: false,
      error
    } as VpnRuntimeStartResultData)
  }

  onDestroy(): void {
    vpnLifecycleInfo('onDestroy enter')
    Logger.debug("VpnExtAbi destroy", "EasyTierAbility")
    this.destroyed = true
    this.lifecycleGeneration++
    this.runtimeInitializationStarted = false
    this.networkWatchdog?.stop()
    this.networkWatchdog = undefined
    this.bridgeServer.publishContinuationState(false)
    if (this.timer) {
      clearInterval(this.timer);
      this.timer = undefined
    }
    this.kernelSocketService.close();
    void this.finishShutdown()
  }

  private async finishShutdown(): Promise<void> {
    if (this.shutdownStarted) {
      return
    }
    this.shutdownStarted = true
    const restartPromise = this.kernelRestartPromise
    if (restartPromise) {
      try {
        await restartPromise
      } catch (error) {
        Logger.debug(`waiting for kernel restart shutdown failed: ${JSON.stringify(error)}`, 'EasyTierAbility')
      }
    }
    await this.stopKernel()
    try {
      await this.tunService?.destroy()
    } finally {
      this.tunService = undefined
      this.bridgeServer.close()
    }
  }

  private startKernel() {
    this.beginKernelGeneration()
    const cfgStr = JSON.stringify(this.config);
    let startResult: VpnRuntimeStartResultData
    if (!easytier.parseNetworkConfig(cfgStr)) {
      Logger.error("Failed to start git_core kernel", "EasyTierAbility");
      stopRuntimeStatsRecording()
      startResult = {
        instanceId: this.instance_id,
        started: false,
        error: 'invalid_config'
      }
    } else if (!easytier.runNetworkInstance(cfgStr)) {
      Logger.error("Failed to start git_core kernel", "EasyTierAbility");
      stopRuntimeStatsRecording()
      startResult = {
        instanceId: this.instance_id,
        started: false,
        error: 'kernel_start_rejected'
      }
    } else {
      startResult = {
        instanceId: this.instance_id,
        started: true
      }
      startRuntimeStatsRecording(this.context.filesDir)
      this.kernelSocketService.connect(this.socketFilesDir + '/' + KERNEL_SOCKET_NAME)
    }
    this.bridgeServer.publishRuntimeStartResult(startResult)
  }

  private beginKernelGeneration(): void {
    this.kernelSocketService.close()
    this.bridgeServer.beginRuntimeGeneration()
  }

  private async stopKernel(): Promise<void> {
    stopRuntimeStatsRecording()
    if (this.instance_id.length > 0) {
      const stopped = await stopStoredInstances([this.instance_id])
      if (!stopped) {
        Logger.error(`Failed to stop kernel instance=${this.instance_id}`, 'EasyTierAbility')
      }
    }
  }

  private startCollecting() {
    this.timer = setInterval(() => {
      this.bridgeServer.forwardLogs(easytier.drainLogLines())
    }, 500);
    this.startNetworkWatchdog()
  }

  /** ext（子进程）模式的切网看护：默认网络切换后只软重启内核实例。 */
  private startNetworkWatchdog() {
    if (this.networkWatchdog) {
      return
    }
    this.networkWatchdog = new NetworkChangeWatchdog({
      logTarget: 'EasyTierAbility',
      getRunningIds: () => {
        return !this.destroyed && this.instance_id.length > 0 ? [this.instance_id] : []
      },
      restartInstances: (ids: string[]) => {
        return this.restartKernelForNetworkChange(ids[0] ?? this.instance_id)
      }
    })
    this.networkWatchdog.start()
  }

  private restartKernelForNetworkChange(instanceId: string): Promise<NetworkRestartResult> {
    if (this.destroyed || this.kernelRestartPromise) {
      const cancelledResult: NetworkRestartResult = {
        stopped: false,
        started: false,
        cancelled: true
      }
      return Promise.resolve(cancelledResult)
    }
    const lifecycleGeneration = this.lifecycleGeneration
    const restartPromise = this.performKernelRestart(instanceId, lifecycleGeneration)
    this.kernelRestartPromise = restartPromise
    const clearRestartPromise = (): void => {
      if (this.kernelRestartPromise === restartPromise) {
        this.kernelRestartPromise = undefined
      }
    }
    restartPromise.then(clearRestartPromise, clearRestartPromise)
    return restartPromise
  }

  private async performKernelRestart(instanceId: string, lifecycleGeneration: number): Promise<NetworkRestartResult> {
    const tunService = this.tunService
    if (!tunService || !await tunService.beginKernelRestart()) {
      return {
        stopped: false,
        started: false,
        cancelled: true
      }
    }
    this.beginKernelGeneration()
    let result: NetworkRestartResult
    try {
      result = await softRestartWithConfig(instanceId, JSON.stringify(this.config), () => {
        return !this.destroyed && lifecycleGeneration === this.lifecycleGeneration
      })
    } catch (error) {
      await tunService.completeKernelRestart(false)
      throw new Error((error as Error).message)
    }
    const lifecycleCurrent = !this.destroyed && lifecycleGeneration === this.lifecycleGeneration
    if (result.started && lifecycleCurrent) {
      this.kernelSocketService.connect(this.socketFilesDir + '/' + KERNEL_SOCKET_NAME)
    }
    await tunService.completeKernelRestart(result.started && lifecycleCurrent)
    if (!lifecycleCurrent && result.started) {
      await stopStoredInstances([instanceId])
      return {
        stopped: result.stopped,
        started: false,
        cancelled: true
      }
    }
    return result
  }
}
