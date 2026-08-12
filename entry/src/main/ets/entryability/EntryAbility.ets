import { AbilityConstant, Configuration, UIAbility, Want, wantConstant } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { EventHelper } from '../util/EventHelper';
import { Logger, LogLocate } from '../shared/logging/Logger';
import { BusinessError, commonEventManager, deviceInfo } from '@kit.BasicServicesKit';
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
    isExtMode: () => false,
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
    this.statusBarIntegrationService?.close()
    this.context.terminateSelf().catch((error: BusinessError) => {
      Logger.error(`terminateSelf failed: ${error.code}, ${error.message}`, this)
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
        this.statusBarIntegrationService?.close()
        setTimeout(() => {
          this.context.terminateSelf().catch((error: BusinessError) => {
            Logger.error(`terminateSelf after status bar exit failed: ${error.code}, ${error.message}`, this)
          })
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

  private shouldProtectProcessNet(config: ConfigJson): boolean {
    return deviceInfo.sdkApiVersion >= 22 && AppManager.uiState.force_global &&
      (config.exit_nodes?.length ?? 0) > 0
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
      }
    })
    this.entryKernelSocketService = new EntryKernelSocketService({
      logTarget: this,
      shouldConnect: () => true,
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
      let config: ConfigJson
      try {
        config = JSON.parse(request.configJson) as ConfigJson
      } catch (_) {
        return false
      }
      if (config.instance_id !== request.instanceId) {
        return false
      }
      if (!config.no_tun) {
        await vpnService.prepareVpnAsync(this.shouldProtectProcessNet(config))
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
      if (instanceIds.length > 0 && !await stopStoredInstances(instanceIds)) {
        return false
      }
      stopRuntimeStatsRecording()
      this.entryKernelSocketService?.close()
      await this.entryVpnService?.destroyVpnConnection()
      this.deactivateMissionContinue()
      return true
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
    if (!easytier.initConfigStore(this.context.filesDir)) {
      Logger.error('main-process Core config store initialization failed', this)
    } else if (!easytier.startNearbyManagementHost()) {
      Logger.error('main-process nearby management host failed to start', this)
    } else {
      this.startNearbyHostCommandDrain()
    }
    startupMark('ability.logManager.init')
    // Main-process runtime owns Core, TUN and physical-network restart transactions.
    this.networkWatchdog = new NetworkChangeWatchdog({
      logTarget: this,
      getRunningIds: () => {
        return AppManager.easytier.getRuntimeIntentIds()
      },
      restartInstances: (ids: string[]) => {
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
    this.thirdPartyApiService?.destroy()
    this.thirdPartyApiService = undefined
    this.networkWatchdog?.stop()
    this.networkWatchdog = undefined
    MemoryDiagnosticsService.enableSystemLeakWatcher(false)
    void RemoteManageService.disconnect()
    RemoteManageService.destroyHostSessions()
    this.stopNearbyHostCommandDrain()
    easytier.stopNearbyManagementHost()
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
