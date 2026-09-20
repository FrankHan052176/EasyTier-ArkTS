import { AbilityConstant, Configuration, UIAbility, Want, wantConstant } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { EventHelper } from '../util/EventHelper';
import { Logger, LogLocate } from '../shared/logging/Logger';
import { BusinessError, commonEventManager, deviceInfo } from '@kit.BasicServicesKit';
import { fileIo } from '@kit.CoreFileKit';
import easytier from 'easytier-ohrs';
import { JSON } from '@kit.ArkTS';
import { BUILD_TIME } from '../util/info/BuildTime';
import { WindowUtil } from '../WindowUtil';
import { publishTextNotification } from '../util/NoticeHelper';
import { HMRouterMgr } from '@hadss/hmrouter';
import { AppManager } from '../AppManager';
import { buildShareUrlSync } from '../util/ShareUtil';
import { FavoriteCardActionService } from '../services/form/FavoriteCardActionService';
import { ContinuationSocketClient } from '../infrastructure/bridge/kernel/ContinuationSocketClient'
import { CrashLogService } from '../services/crash/CrashLogService'
import { MemoryDiagnosticsService } from '../services/runtime/MemoryDiagnosticsService'
import { EntryBackgroundTaskService } from '../services/runtime/EntryBackgroundTaskService'
import { EntryAppBootstrapService } from '../services/runtime/EntryAppBootstrapService'
import { RemoteManageService } from '../services/remote/RemoteManageService'
import {
  UPDATE_COLOR_MODE_EVENT
} from '../types/events/RuntimeEventTypes'
import { SharedIntentImportService } from '../services/share/SharedIntentImportService'
import { StatusBarIntegrationService } from '../services/desktop/StatusBarIntegrationService'
import {
  NetworkChangeWatchdog,
  NetworkRestartResult,
  startOneShotInstance,
  startStoredInstances,
  stopStoredInstances
} from '../services/runtime/NetworkChangeWatchdog'
import { startupMark } from '../services/runtime/StartupTrace'
import {
  registerEntryKeepAliveHandlers,
  unregisterEntryKeepAliveHandlers
} from '../services/runtime/EntryKeepAliveBridge'
import {
  setStatusBarTraySupported,
  supportsStatusBarTray,
  STATUS_BAR_BACKGROUND_TERMINATE_EVENT,
  VPN_EXTENSION_SOCKET_NAME
} from '../services/runtime/AbilityRuntimePolicy'
import { ThirdPartyApiService } from '../services/integration/ThirdPartyApiService'
import { ConfigJson } from '../config/schema/SchemaConfig'
import { KERNEL_SOCKET_NAME } from '../infrastructure/bridge/kernel/KernelBridgeTypes'
import { EntryKernelSocketService } from '../services/runtime/EntryKernelSocketService'
import {
  EntryRuntimeStartRequest,
  registerEntryRuntimeHandlers,
  unregisterEntryRuntimeHandlers
} from '../services/runtime/EntryRuntimeStopBridge'
import { EntryVpnConnectionService } from '../services/tun/EntryVpnConnectionService'
import { EntryVpnSetupRequestBuilder } from '../services/tun/EntryVpnSetupRequestBuilder'
import { startRuntimeStatsRecording, stopRuntimeStatsRecording } from '../services/runtime/RuntimeStatsService'
import { RuntimeHostLease } from '../services/runtime/RuntimeHostLease'
import { IapService } from '../services/iap/IapService'

interface NearbyHostCommandData {
  requestId: string
  operation: string
  instanceId: string
  configJson?: string
}

/**
 * 模拟器测试用的手机比例窗口尺寸（px），仅在 productModel === 'emulator' 时生效。
 * 模拟器密度 1.9，取 722x1482px ≈ 380x780vp，与真机（约 376x742vp）对齐，
 * 保证 uiType 落在 Column_1 且每屏可见行数与真机一致。
 */
const EMULATOR_WINDOW_WIDTH_PX = 722
const EMULATOR_WINDOW_HEIGHT_PX = 1482

/**
 * Core（easytier-ohrs nearby_management.rs MANAGEMENT_SOCKET_FILE_NAME）在
 * config_root_dir 下绑定的管理宿主 socket。停止宿主只做 take/drop，unlink 在
 * Drop 中异步完成，因此必须观察该路径消失才能认定旧宿主已真正释放。
 *
 * 路径本身证明不了持有者是否还活着（进程崩溃会残留路径），所以"谁是宿主"由
 * RuntimeHostLease 的进程间文件锁证明：锁在手里才允许调 native start。
 */
const NEARBY_MANAGEMENT_SOCKET_NAME = 'easytier-nearby-management.sock'
const NEARBY_HOST_RELEASE_POLL_MS = 25
const NEARBY_HOST_RELEASE_TIMEOUT_MS = 5000

function delay(milliseconds: number): Promise<void> {
  return new Promise<void>((resolve) => {
    setTimeout(resolve, milliseconds)
  })
}

@LogLocate("EntryAbility")
export default class EntryAbility extends UIAbility {
  private entryVpnService: EntryVpnConnectionService | undefined = undefined
  private entryKernelSocketService: EntryKernelSocketService | undefined = undefined
  private networkWatchdog: NetworkChangeWatchdog | undefined = undefined
  private entryBackgroundTaskService: EntryBackgroundTaskService | undefined = undefined
  private entryAppBootstrapService: EntryAppBootstrapService | undefined = undefined
  private statusBarIntegrationService: StatusBarIntegrationService | undefined = undefined
  private statusBarSubscriber: commonEventManager.CommonEventSubscriber | undefined = undefined
  private mainWindow: window.Window | undefined = undefined
  private mainWindowReadyPromise: Promise<window.Window> | undefined = undefined
  private mainWindowReadyResolver: ((mainWindow: window.Window) => void) | undefined = undefined
  private windowWillCloseCallback: (() => Promise<boolean>) | undefined = undefined
  private windowStageCloseCallback: (() => boolean) | undefined = undefined
  private continuationSocketClient: ContinuationSocketClient = new ContinuationSocketClient({
    socketName: VPN_EXTENSION_SOCKET_NAME,
    logTarget: 'EntryAbility',
    isExtMode: () => AppManager.uiState.ext_mode,
    getSocketPath: (name: string) => AppManager.uiState.getSocketPath(name),
    onContinueState: (active: boolean) => {
      if (active) {
        this.activateMissionContinue()
      } else {
        this.deactivateMissionContinue()
      }
    }
  })
  private appReadyPromise: Promise<void> = Promise.resolve()
  private thirdPartyApiService: ThirdPartyApiService | undefined = undefined
  private favoriteCardActions: FavoriteCardActionService = new FavoriteCardActionService()
  private nearbyHostTimer: number | undefined = undefined
  private nearbyHostCommandQueue: Promise<void> = Promise.resolve()
  /**
   * 本进程是否真正持有 Core nearby 管理宿主。只有本进程成功调用过
   * startNearbyManagementHost() 才允许 stop，避免 remove_file 掉扩展
   * 进程或下一条生命周期的同名 socket。
   */
  private nearbyHostOwned: boolean = false
  /**
   * 本进程停过宿主但尚未观察到 socket 路径消失。超时后仍保持为 true，
   * 使后续取宿主/交接必须继续等待，不会被 owned=false 绕过。
   */
  private nearbyHostReleasePending: boolean = false
  /**
   * nearby 宿主的进程间所有权凭证。context.filesDir 确定后建立；只有锁在手里才
   * 允许 native start。锁随持有进程存活（进程崩溃时 OS 释放 fd 锁），因此残留的
   * socket 路径不再永久挡住冷启动。
   */
  private nearbyHostLease: RuntimeHostLease | undefined = undefined
  private configStoreReady: boolean = false
  private runtimeHostSyncQueue: Promise<void> = Promise.resolve()
  private terminating: boolean = false
  private vpnSetupRequestBuilder: EntryVpnSetupRequestBuilder = new EntryVpnSetupRequestBuilder({
    getRuntimeSettings: () => {
      return {
        vpnRoutes: AppManager.uiState.vpn_routes,
        whiteList: AppManager.uiState.white_list,
        blackList: AppManager.preference.getBlackList(),
        dev: AppManager.uiState.dev,
        dns: AppManager.uiState.dns
      }
    }
  })
  private activateMissionContinue(): void {
    this.context.setMissionContinueState(AbilityConstant.ContinueState.ACTIVE)
  }

  private deactivateMissionContinue(): void {
    this.context.setMissionContinueState(AbilityConstant.ContinueState.INACTIVE)
  }

  private syncContinuationSocket(): void {
    this.continuationSocketClient.sync()
  }

  private shouldMinimizeToBackground(): boolean {
    return supportsStatusBarTray()
  }

  private hideMainWindow(): Promise<boolean> {
    try {
      return this.context.hideAbility().then(() => {
        Logger.info('main window hidden to status bar', this)
        return true
      }).catch((err: BusinessError) => {
        Logger.error(`hideAbility failed: ${err.code}, ${err.message}`, this)
        return false
      })
    } catch (err) {
      Logger.error(`hideAbility error: ${JSON.stringify(err)}`, this)
      return Promise.resolve(false)
    }
  }

  private restoreMainWindow(): void {
    if (!this.shouldMinimizeToBackground()) {
      return
    }
    this.context.showAbility().catch((err: BusinessError) => {
      Logger.debug(`showAbility ignored: ${err.code}, ${err.message}`, this)
    })
    if (!this.mainWindow) {
      return
    }
    try {
      this.mainWindow.restore().catch((err: BusinessError) => {
        Logger.debug(`main window restore ignored: ${err.code}, ${err.message}`, this)
      })
    } catch (err) {
      Logger.debug(`main window restore error ignored: ${JSON.stringify(err)}`, this)
    }
  }

  private terminateApplication(): void {
    if (this.terminating) {
      return
    }
    this.terminating = true
    this.statusBarIntegrationService?.close()
    void this.stopEntryRuntimeForTermination().then(() => {
      return this.context.terminateSelf()
    }).catch((error: BusinessError) => {
      Logger.error(`application termination failed: ${error.code ?? 0}, ${error.message}`, this)
    })
  }

  private async stopEntryRuntimeForTermination(): Promise<void> {
    try {
      await AppManager.easytier.stopAndWait()
    } catch (error) {
      Logger.error(`runtime stop before termination failed: ${(error as Error).message}`, this)
    }
    try {
      await this.entryVpnService?.destroyVpnConnection()
    } catch (error) {
      Logger.error(`vpn destroy before termination failed: ${(error as Error).message}`, this)
    }
  }

  private handleSocketProtectionFatal(error: Error): void {
    Logger.error(`socket protection fatal error: ${error.message}`, this)
    void AppManager.easytier.stopAndWait().catch((stopError: Error) => {
      Logger.error(`runtime stop after socket protection failure failed: ${stopError.message}`, this)
    }).then(async () => {
      await this.entryVpnService?.destroyVpnConnection()
    }).catch((destroyError: Error) => {
      Logger.error(`vpn destroy after socket protection failure failed: ${destroyError.message}`, this)
    })
  }

  private waitMainWindowReady(): Promise<window.Window> {
    if (this.mainWindow) {
      return Promise.resolve(this.mainWindow)
    }
    if (!this.mainWindowReadyPromise) {
      this.mainWindowReadyPromise = new Promise<window.Window>((resolve) => {
        this.mainWindowReadyResolver = resolve
      })
    }
    return this.mainWindowReadyPromise
  }

  private notifyMainWindowReady(mainWindow: window.Window): void {
    this.mainWindowReadyResolver?.(mainWindow)
    this.mainWindowReadyResolver = undefined
  }

  private shouldStartStatusBar(mainWindow: window.Window): boolean {
    const deviceType = deviceInfo.deviceType.toLowerCase()
    if (deviceType === '2in1' || deviceType === 'pc') {
      Logger.info(`status bar enabled for deviceType=${deviceType}`, this)
      return true
    }
    if (deviceType !== 'tablet') {
      Logger.info(`status bar skipped for deviceType=${deviceType}`, this)
      return false
    }
    if (deviceInfo.sdkApiVersion < 12) {
      Logger.info(`status bar skipped for tablet sdkApiVersion=${deviceInfo.sdkApiVersion}`, this)
      return false
    }
    try {
      const status = mainWindow.getWindowStatus()
      const enabled = status === window.WindowStatusType.FLOATING
      Logger.info(`status bar tablet windowStatus=${status}, enabled=${enabled}`, this)
      return enabled
    } catch (error) {
      Logger.debug(`status bar tablet window status check failed: ${JSON.stringify(error)}`, this)
      return false
    }
  }

  private registerWindowCloseToBackground(windowStage: window.WindowStage, mainWindow: window.Window): void {
    if (deviceInfo.sdkApiVersion >= 15) {
      this.windowWillCloseCallback = () => {
        if (!this.shouldMinimizeToBackground()) {
          return Promise.resolve(false)
        }
        return this.hideMainWindow()
      }
      try {
        mainWindow.on('windowWillClose', this.windowWillCloseCallback)
      } catch (err) {
        Logger.debug(`windowWillClose register ignored: ${JSON.stringify(err)}`, this)
      }
    }
    if (deviceInfo.sdkApiVersion >= 14) {
      this.windowStageCloseCallback = () => {
        if (!this.shouldMinimizeToBackground()) {
          return false
        }
        void this.hideMainWindow()
        return true
      }
      try {
        windowStage.on('windowStageClose', this.windowStageCloseCallback)
      } catch (err) {
        Logger.debug(`windowStageClose register ignored: ${JSON.stringify(err)}`, this)
      }
    }
  }

  private subscribeStatusBarTerminateEvent(): void {
    if (this.statusBarSubscriber) {
      return
    }
    const subscribeInfo: commonEventManager.CommonEventSubscribeInfo = {
      events: [STATUS_BAR_BACKGROUND_TERMINATE_EVENT]
    }
    commonEventManager.createSubscriber(subscribeInfo).then((subscriber: commonEventManager.CommonEventSubscriber) => {
      this.statusBarSubscriber = subscriber
      commonEventManager.subscribe(subscriber, (err: BusinessError) => {
        if (err) {
          Logger.error(`status bar terminate subscribe failed: ${err.code}, ${err.message}`, this)
          return
        }
        setTimeout(() => {
          this.terminateApplication()
        }, 200)
      })
    }).catch((err: BusinessError) => {
      Logger.error(`status bar terminate subscriber create failed: ${err.code}, ${err.message}`, this)
    })
  }

  private unsubscribeStatusBarTerminateEvent(): void {
    if (!this.statusBarSubscriber) {
      return
    }
    commonEventManager.unsubscribe(this.statusBarSubscriber, (err?: BusinessError) => {
      if (err) {
        Logger.debug(`status bar terminate unsubscribe ignored: ${err.code}, ${err.message}`, this)
      }
    })
    this.statusBarSubscriber = undefined
  }

  stopContinuousTask(): void {
    void this.entryBackgroundTaskService?.stopContinuousTask().catch((error: Error) => {
      Logger.error(`stop continuous task failed: ${error.message}`, this)
    })
  }

  private startNearbyHostCommandDrain(): void {
    if (this.nearbyHostTimer !== undefined) {
      return
    }
    this.nearbyHostTimer = setInterval(() => {
      this.drainNearbyHostCommands()
    }, 500)
  }

  private stopNearbyHostCommandDrain(): void {
    if (this.nearbyHostTimer === undefined) {
      return
    }
    clearInterval(this.nearbyHostTimer)
    this.nearbyHostTimer = undefined
  }

  private ensureEntryConfigStore(): boolean {
    if (this.configStoreReady) {
      return true
    }
    if (!easytier.initConfigStore(this.context.filesDir)) {
      return false
    }
    this.configStoreReady = true
    return true
  }

  private nearbyManagementSocketPath(): string {
    return this.context.filesDir + '/' + NEARBY_MANAGEMENT_SOCKET_NAME
  }

  private isNearbyManagementSocketPresent(): boolean {
    try {
      return fileIo.accessSync(this.nearbyManagementSocketPath())
    } catch (error) {
      // 探针失败的保守结论是“仍在”，宁可等待超时也不误判为已释放。
      Logger.debug(`nearby management socket probe failed: ${JSON.stringify(error)}`, this)
      return true
    }
  }

  /**
   * 有界等待本进程停掉的宿主真正释放：Core 的 stop 只 take/drop，
   * socket unlink 在 Drop 中异步完成，返回并不代表已删除。
   * 只有观察到路径消失才清 releasePending；超时保持 pending，
   * 下一次取宿主仍必须继续等待。
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
        Logger.info('previous nearby management host released', this)
        return true
      }
      await delay(NEARBY_HOST_RELEASE_POLL_MS)
    }
    Logger.error(`nearby management socket still present after release timeout: ${socketPath}`, this)
    return false
  }

  /**
   * 主模式：本进程持有 Core 管理宿主与命令 drain。
   *
   * 归属证明是宿主锁而不是 socket 路径是否存在：活着的持有者（UI 或扩展进程）
   * 一直握着锁，所以拿不到锁就拒绝启动；持有者进程崩溃时 OS 会随 fd 释放锁，
   * 于是残留路径不再永久挡住冷启动——此时由 native 的
   * startNearbyManagementHost() 自己清理 stale 路径。
   */
  private async ensureOwnedNearbyHost(): Promise<boolean> {
    if (!this.ensureEntryConfigStore()) {
      Logger.error('main-process Core config store initialization failed', this)
      return false
    }
    const lease = this.nearbyHostLease
    if (!lease) {
      Logger.error('main-process nearby host lease unavailable', this)
      return false
    }
    if (this.nearbyHostOwned) {
      this.startNearbyHostCommandDrain()
      return true
    }
    // 幂等：本进程已持有锁时直接成功；别的进程持有则绝不启动第二个宿主。
    if (!lease.tryAcquire()) {
      Logger.error('main-process nearby management host not acquired: lease held by another process', this)
      return false
    }
    // 锁只证明没有别的活宿主；自家上一任宿主的 socket 还必须观察到真正消失，
    // 否则 native start 可能与晚到的 Drop unlink 抢同一个路径。
    if (!await this.awaitNearbyHostRelease()) {
      return false
    }
    if (!easytier.startNearbyManagementHost()) {
      Logger.error('main-process nearby management host failed to start', this)
      // native 没起来：不留着自己拿到的锁，否则下一任永远无法接管。
      lease.release()
      return false
    }
    this.nearbyHostOwned = true
    this.startNearbyHostCommandDrain()
    Logger.info('main-process nearby management host ready', this)
    return true
  }

  /**
   * 子进程模式或 UI 生命周期结束：只释放本进程真正持有的宿主。
   * 扩展进程的宿主由其自身释放，UI 绝不能代为 unlink。
   *
   * 宿主锁不在这里释放：必须观察到 socket 路径真正消失之后才 release
   * （见 applyRuntimeHostMode / releaseNearbyHostLeaseAfterNativeRelease）。
   */
  private stopOwnedNearbyHost(): void {
    this.stopNearbyHostCommandDrain()
    if (!this.nearbyHostOwned) {
      return
    }
    this.nearbyHostOwned = false
    this.nearbyHostReleasePending = true
    if (!easytier.stopNearbyManagementHost()) {
      Logger.warn('main-process nearby management host stop was rejected', this)
    }
  }

  /**
   * 交还宿主锁：排在 runtimeHostSyncQueue 之后，先重查一次原生宿主是否被在途的
   * 模式切换拿起来、停掉它，再等 socket 路径真正消失，最后才 release。
   * 释放未证实则保留锁与 releasePending，让下一任继续拒绝接管。
   */
  private releaseNearbyHostLeaseAfterNativeRelease(): void {
    const lease = this.nearbyHostLease
    if (!lease) {
      return
    }
    const operation = this.runtimeHostSyncQueue.catch(() => {}).then(async () => {
      this.stopOwnedNearbyHost()
      if (!await this.awaitNearbyHostRelease()) {
        Logger.error('nearby host lease retained: native host release unconfirmed', this)
        return
      }
      lease.release()
      Logger.info('nearby host lease released after native host release', this)
    })
    this.runtimeHostSyncQueue = operation.catch((error: Error) => {
      Logger.error(`nearby host lease release failed: ${error.message}`, this)
    })
  }

  private async releaseEntryVpnConnectionIfIdle(): Promise<void> {
    if (AppManager.easytier.hasActiveOrStartingRuntime()) {
      Logger.warn('runtime host sync kept the UI vpn connection: runtime still active', this)
      return
    }
    try {
      await this.entryVpnService?.destroyVpnConnection()
    } catch (error) {
      Logger.error(`vpn destroy during runtime host sync failed: ${(error as Error).message}`, this)
    }
  }

  /**
   * 按 AppManager.uiState.ext_mode 归一化 UI 进程侧的运行宿主：
   * 子进程模式释放 UI 的 nearby host/命令 drain/内核 socket/空闲 VPN 并等待
   * 释放被证实，然后才交还宿主锁；主模式确保 UI 持有 nearby host 与命令 drain
   * （内核 socket 由启动闭包建立）。释放无法证实即返回 false 并保留锁与 pending，
   * 绝不让下一方在脏路径上启动。
   */
  private async applyRuntimeHostMode(): Promise<boolean> {
    const extMode = AppManager.uiState.ext_mode
    this.syncContinuationSocket()
    if (extMode) {
      this.stopNearbyHostCommandDrain()
      this.entryKernelSocketService?.close()
      await this.releaseEntryVpnConnectionIfIdle()
      this.stopOwnedNearbyHost()
      // native 宿主释放被证实之前绝不解锁：否则扩展进程/主进程的 lease 探测会把
      // 仍在清理宿主的本进程当成已退出。
      if (!await this.awaitNearbyHostRelease()) {
        return false
      }
      this.nearbyHostLease?.release()
      Logger.info('runtime host released to vpn extension process', this)
      return true
    }
    return await this.ensureOwnedNearbyHost()
  }

  private syncRuntimeHost(): Promise<boolean> {
    const operation = this.runtimeHostSyncQueue.catch(() => {}).then(async () => {
      return await this.applyRuntimeHostMode()
    })
    this.runtimeHostSyncQueue = operation.then(() => {}, () => {})
    return operation
  }

  private drainNearbyHostCommands(): void {
    const commands = easytier.drainNearbyHostCommands() as NearbyHostCommandData[]
    for (const command of commands) {
      const operation = this.nearbyHostCommandQueue.catch(() => {}).then(async () => {
        let success = false
        let error = ''
        if (command.operation === 'stop') {
          try {
            await AppManager.easytier.stopAndWait()
            success = true
          } catch (stopError) {
            error = (stopError as Error).message
          }
        } else if (command.operation === 'start_once' && command.configJson) {
          let config: ConfigJson | undefined = undefined
          try {
            config = JSON.parse(command.configJson) as ConfigJson
          } catch (_) {
            error = 'one_shot_config_invalid'
          }
          if (config && config.instance_id === command.instanceId) {
            success = await AppManager.easytier.startNearbyOneShot(command.requestId, command.configJson)
            if (!success) {
              error = 'one_shot_runtime_start_failed'
            }
          } else if (error.length === 0) {
            error = 'one_shot_config_instance_mismatch'
          }
        } else {
          error = 'nearby_host_command_invalid'
        }
        const completed = easytier.completeNearbyHostCommand(command.requestId, success,
          error.length > 0 ? error : undefined)
        if (!completed && success && command.operation === 'start_once') {
          await AppManager.easytier.rollbackNearbyOneShot(command.requestId)
        }
      })
      this.nearbyHostCommandQueue = operation.catch((error: Error) => {
        Logger.error(`nearby host command failed request=${command.requestId}: ${error.message}`, this)
        easytier.completeNearbyHostCommand(command.requestId, false, error.message)
      })
    }
  }

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam) {
    startupMark('ability.onCreate.begin')
    this.thirdPartyApiService = new ThirdPartyApiService(this.context)
    this.deactivateMissionContinue();
    this.entryVpnService = new EntryVpnConnectionService({
      context: this.context,
      logTarget: this,
      requestVpnPerm: (callback: () => void, errorCallback?: (error: BusinessError) => void) => {
        AppManager.permission.requestVpnPerm(callback, () => {}, errorCallback)
      },
      activateMissionContinue: () => {
        this.activateMissionContinue()
      },
      setTunFd: (instanceId: string, fd: number) => {
        const attached = easytier.setTunFd(instanceId, fd)
        Logger.info(`setTunFd sent instance=${instanceId} attached=${attached}`, this)
        return attached
      },
      onProtectionFatal: (error: Error) => {
        this.handleSocketProtectionFatal(error)
      }
    })
    this.entryKernelSocketService = new EntryKernelSocketService({
      logTarget: this,
      shouldConnect: () => !AppManager.uiState.ext_mode,
      buildTunSetupRequest: (payload) => {
        return this.vpnSetupRequestBuilder.buildFromKernelPayload(payload)
      },
      setupTun: (request) => {
        void this.entryVpnService?.setupTun(request)
      }
    })
    registerEntryRuntimeHandlers(async (request: EntryRuntimeStartRequest): Promise<boolean> => {
      const vpnService = this.entryVpnService
      if (!vpnService) {
        return false
      }
      if (AppManager.uiState.ext_mode) {
        // 子进程模式：内核宿主在扩展进程，UI 不建立 VPN 授权/内核 socket。
        Logger.warn('main-process runtime start rejected: vpn extension mode active', this)
        return false
      }
      let config: ConfigJson
      try {
        config = JSON.parse(request.configJson) as ConfigJson
      } catch (_) {
        return false
      }
      if (config.instance_id !== request.instanceId) {
        return false
      }
      if (!await this.ensureOwnedNearbyHost()) {
        return false
      }
      if (!config.no_tun) {
        await vpnService.prepareVpnAsync()
      }
      this.entryKernelSocketService?.connect(this.context.filesDir + '/' + KERNEL_SOCKET_NAME)
      const started = request.oneShot ? await startOneShotInstance(request.configJson) :
        await startStoredInstances([request.instanceId])
      if (started) {
        startRuntimeStatsRecording(this.context.filesDir)
        return true
      }
      this.entryKernelSocketService?.close()
      await vpnService.destroyVpnConnection()
      return false
    }, async (instanceIds: string[]): Promise<boolean> => {
      if (AppManager.uiState.ext_mode) {
        Logger.warn('main-process runtime stop rejected: vpn extension mode active', this)
        return false
      }
      if (instanceIds.length > 0 && !await stopStoredInstances(instanceIds)) {
        return false
      }
      stopRuntimeStatsRecording()
      this.entryKernelSocketService?.close()
      await this.entryVpnService?.destroyVpnConnection()
      this.deactivateMissionContinue()
      return true
    }, async (): Promise<boolean> => {
      return await this.syncRuntimeHost()
    })
    this.entryBackgroundTaskService = new EntryBackgroundTaskService({
      context: this.context,
      logTarget: this,
      setNotificationId: (notificationId: number) => {
        AppManager.uiState.notificationId = notificationId
      },
      clearNotificationId: () => {
        AppManager.uiState.notificationId = undefined
      },
      getBackgroundKeepAliveMode: () => {
        return AppManager.uiState.background_keep_alive_mode
      },
      onBackgroundTaskCancelled: (reason: string) => {
        Logger.error(`background keep-alive cancelled reason=${reason}`, this)
        CrashLogService.recordRuntimeSignal(this.context.filesDir, 'continuous_task_cancelled', reason)
      },
      onBackgroundTaskSuspended: (reason: string) => {
        Logger.warn(`background keep-alive suspended reason=${reason}`, this)
        CrashLogService.recordRuntimeSignal(this.context.filesDir, 'continuous_task_suspended', reason)
        publishTextNotification('后台保活已暂停，打开应用后将自动恢复')
      },
      onBackgroundTaskActive: () => {
        CrashLogService.recordRuntimeSignal(this.context.filesDir, 'continuous_task_active', '')
      }
    })
    registerEntryKeepAliveHandlers(async (name: string | undefined): Promise<boolean> => {
      return await this.entryBackgroundTaskService?.startContinuousTask(name) ?? false
    }, async () => {
      await this.entryBackgroundTaskService?.stopContinuousTask()
    })
    this.entryAppBootstrapService = new EntryAppBootstrapService({
      context: this.context,
      logTarget: this,
      syncContinuationSocket: () => {
        this.syncContinuationSocket()
      }
    })
    this.statusBarIntegrationService = new StatusBarIntegrationService(this.context, this, () => {
      this.restoreMainWindow()
    }, () => {
      this.terminateApplication()
    })
    this.subscribeStatusBarTerminateEvent()
    this.favoriteCardActions.start(this.callee)
    startupMark('ability.onCreate.services')
    CrashLogService.init(this.context.filesDir)
    CrashLogService.recordLastExit(this.context.filesDir, launchParam)
    startupMark('ability.crashLog.init')
    easytier.initLogManager(this.context.filesDir, 'ui')
    easytier.configureLogManager(false, false)
    // 仅初始化 UI 侧配置读写；运行宿主归属等 preferences 载入后由 syncRuntimeHost 决定，
    // 子进程模式下 UI 绝不启动 nearby host / 内核 socket。
    if (!this.ensureEntryConfigStore()) {
      Logger.error('main-process Core config store initialization failed', this)
    }
    // root（context.filesDir）已确定：建立宿主锁对象。真正加锁发生在申请宿主时，
    // 保证"持有锁"与"持有 native 宿主"始终一致。
    this.nearbyHostLease = new RuntimeHostLease(this.context.filesDir)
    startupMark('ability.logManager.init')
    // 主进程运行时持有 Core、TUN 与物理网络重启事务；子进程模式下内核宿主在扩展进程，
    // 该进程不参与看护（由 EasyTierAbility 自己的 watchdog 负责）。
    this.networkWatchdog = new NetworkChangeWatchdog({
      logTarget: this,
      getRunningIds: () => {
        if (AppManager.uiState.ext_mode) {
          return []
        }
        return AppManager.easytier.getRuntimeIntentIds()
      },
      restartInstances: (ids: string[]) => {
        if (AppManager.uiState.ext_mode) {
          const extensionResult: NetworkRestartResult = {
            stopped: false,
            started: false,
            cancelled: true
          }
          return Promise.resolve(extensionResult)
        }
        const vpnService = this.entryVpnService
        if (!vpnService) {
          const cancelledResult: NetworkRestartResult = {
            stopped: false,
            started: false,
            cancelled: true
          }
          return Promise.resolve(cancelledResult)
        }
        return AppManager.easytier.restartForNetworkChange(ids, () => {
          return vpnService.beginKernelRestart()
        }, async (started: boolean, stopped: boolean): Promise<void> => {
          await vpnService.completeKernelRestart(started, stopped)
          if (stopped && !started) {
            stopRuntimeStatsRecording()
            this.entryKernelSocketService?.close()
            this.deactivateMissionContinue()
          }
        })
      }
    })
    this.networkWatchdog.start()
    startupMark('ability.netWatchdog.start')
    HMRouterMgr.openLog("INFO")
    HMRouterMgr.init({
      context: this.context
    })
    startupMark('ability.hmrouter.init')
    Logger.info("BuildTime:" + BUILD_TIME, this)
    WindowUtil.colorMode = this.context.config.colorMode ?? -1
    this.appReadyPromise = this.startStatusBarThenInitApp()
    this.appReadyPromise.then(() => {
      this.thirdPartyApiService?.start()
      this.handleIncomingWant(want, launchParam)
      easytier.initPanicHook()
    }).catch((error: Error) => {
      Logger.error(`application initialization failed: ${error.message}`, this)
    })
  }

  onCollaborate(wantParam: Record<string, Object>): AbilityConstant.CollaborateResult {
    Logger.info("onCollaborate", this)
    const result = RemoteManageService.handleCollaborate(this.context, wantParam, this.appReadyPromise)
    return result === 0 ? AbilityConstant.CollaborateResult.ACCEPT : AbilityConstant.CollaborateResult.REJECT
  }

  async initApp() {
    await this.entryAppBootstrapService?.initialize()
    // preferences 载入后才知晓 ext_mode。主模式不在冷启时抢宿主：可能还活着的
    // 扩展由 Main 的 prepareRuntimeHost 负责处理；子进程模式只做宿主让位，
    // 不申请 VPN 授权、不启动扩展。
    if (!AppManager.uiState.ext_mode) {
      return
    }
    const released = await this.syncRuntimeHost()
    if (!released) {
      Logger.error('runtime host release failed for vpn extension mode', this)
    }
  }

  private async startStatusBarThenInitApp(): Promise<void> {
    const mainWindow = await this.waitMainWindowReady()
    try {
      if (this.shouldStartStatusBar(mainWindow)) {
        await this.statusBarIntegrationService?.start()
      } else {
        setStatusBarTraySupported(false)
      }
    } catch (error) {
      Logger.error(`status bar integration start failed: ${JSON.stringify(error)}`, this)
    }
    await this.initApp()
  }

  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam) {
    Logger.debug("onNetWant", this)
    this.restoreMainWindow()
    this.appReadyPromise.then(() => {
      this.handleIncomingWant(want, launchParam)
    }).catch((error: Error) => {
      Logger.error(`handle new Want failed: ${error.message}`, this)
    })
  }

  private handleIncomingWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    if (ThirdPartyApiService.isRequestWant(want)) {
      void this.thirdPartyApiService?.handleWant(want)
      this.favoriteCardActions.refresh()
      return
    }
    void this.readSharedData(want)
    this.favoriteCardActions.refresh()
    if (launchParam.launchReason === AbilityConstant.LaunchReason.CONTINUATION) {
      if (want.parameters !== undefined) {
        let url = want.parameters.data as string
        this.readUri(url)
      }
    }
  }

  readUri(uri: string | undefined) {
    SharedIntentImportService.readUri(uri)
  }

  async readSharedData(want: Want) {
    await SharedIntentImportService.readSharedData(want, this.context.cacheDir)
  }

  onDestroy() {
    Logger.debug("onDestroy", this)
    const vpnService = this.entryVpnService
    this.entryVpnService = undefined
    void vpnService?.destroyVpnConnection().catch((error: Error) => {
      Logger.error(`vpn destroy during ability shutdown failed: ${error.message}`, this)
    })
    this.thirdPartyApiService?.destroy()
    this.thirdPartyApiService = undefined
    this.networkWatchdog?.stop()
    this.networkWatchdog = undefined
    MemoryDiagnosticsService.enableSystemLeakWatcher(false)
    void RemoteManageService.disconnect()
    RemoteManageService.destroyHostSessions()
    // 只释放 UI 本地资源：子进程模式下的扩展宿主与运行实例由扩展进程自己持有，
    // 这里既不停止子进程、也不写扩展统计。
    this.stopOwnedNearbyHost()
    // 宿主锁的释放是异步的：等自家 native 宿主被证实释放（socket 路径消失）之后才
    // 交还，绝不在 stop 之后立刻 unlock，也不会把锁永远挂在已停的宿主上。
    this.releaseNearbyHostLeaseAfterNativeRelease()
    AppManager.easytier.destroy()
    this.entryBackgroundTaskService?.stopTaskMonitoring()
    unregisterEntryKeepAliveHandlers()
    unregisterEntryRuntimeHandlers()
    this.entryKernelSocketService?.close()
    this.continuationSocketClient.close()
    this.statusBarIntegrationService?.close()
    this.unsubscribeStatusBarTerminateEvent()
    this.favoriteCardActions.stop()
  }

  onPrepareToTerminate(): boolean {
    return false
  }

  async onContinue(wantParam: Record<string, Object>): Promise<AbilityConstant.OnContinueResult> {
    if (AppManager.easytier.runningNetworks.size > 0) {
      let uuid = AppManager.easytier.runningNetworks.keys().next().value as string
      let cfg: ConfigJson | undefined = AppManager.easytier.getConfig(uuid)
      if (cfg) {
        Logger.debug(`continuation config found id=${cfg.instance_id ?? ''}`, this)
        wantParam['data'] = await buildShareUrlSync(cfg, true)
        wantParam[wantConstant.Params.SUPPORT_CONTINUE_SOURCE_EXIT_KEY] = false;
        AppManager.easytier.stop()
        return AbilityConstant.OnContinueResult.AGREE;
      }else {
        return AbilityConstant.OnContinueResult.MISMATCH;
      }
    }else {
      return AbilityConstant.OnContinueResult.MISMATCH;
    }
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    startupMark('ability.onWindowStageCreate')
    try {
      const mainWindow = windowStage.getMainWindowSync()
      this.mainWindow = mainWindow
      this.notifyMainWindowReady(mainWindow)
      this.registerWindowCloseToBackground(windowStage, mainWindow)
      mainWindow.on('windowSizeChange', (data) => {
        WindowUtil.update(data.width, data.height)
      });
      mainWindow.on('avoidAreaChange', (data) => {
        if (data.type == window.AvoidAreaType.TYPE_SYSTEM) {
          WindowUtil.setStatusBarHeight = data.area.topRect.height
        } else if (data.type == window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR) {
          WindowUtil.setNavigationBarHeight = data.area.bottomRect.height
        }
      })
      // 仅模拟器：2in1 默认窗口很宽，会走到 Column_2/Column_3 的多列断点，
      // 布局与手机完全不同，性能对比会失真。强制成手机比例窗口。
      if (deviceInfo.productModel === 'emulator') {
        try {
          mainWindow.resize(EMULATOR_WINDOW_WIDTH_PX, EMULATOR_WINDOW_HEIGHT_PX)
        } catch (error) {
          Logger.error(`emulator window resize failed: ${JSON.stringify(error)}`, this)
        }
      }
    } catch (error) {
    }
    windowStage.loadContent('pages/HMRouterIndex', (err) => {
      startupMark('ability.loadContent.done')
      if (err.code) {
        Logger.error('Failed to load the content. Cause: ' + JSON.stringify(err), this);
        return;
      }
    });
  }

  onWindowStageDestroy(): void {
    this.mainWindow = undefined
    this.windowWillCloseCallback = undefined
    this.windowStageCloseCallback = undefined
    WindowUtil.windowStageDestroy()
  }

  onForeground(): void {
    WindowUtil.foreground()
    AppManager.easytier.setUiForeground(true)
    AppManager.runtimeStats.setUiForeground(true)
    this.syncContinuationSocket()
    void IapService.refreshEntitlementOnForeground(this.context)
  }

  onBackground(): void {
    WindowUtil.background()
    AppManager.easytier.setUiForeground(false)
    AppManager.runtimeStats.setUiForeground(false)
    void RemoteManageService.disconnect()
  }

  onConfigurationUpdate(newConfig: Configuration): void {
    WindowUtil.colorMode = newConfig.colorMode ?? -1
    EventHelper.emitterPublish(UPDATE_COLOR_MODE_EVENT)
  }

}
