import { AbilityConstant, Configuration, UIAbility, Want, wantConstant } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { EventHelper } from '../util/EventHelper';
import { Logger, LogLocate } from '../shared/logging/Logger';
import { BusinessError, deviceInfo, emitter } from '@kit.BasicServicesKit';
import easytier from 'easytier-ohrs';
import { JSON } from '@kit.ArkTS';
import { BUILD_TIME } from '../util/info/BuildTime';
import { WindowUtil } from '../WindowUtil';
import { HMRouterMgr } from '@hadss/hmrouter';
import { AppManager } from '../AppManager';
import { buildShareUrlSync } from '../util/ShareUtil';
import { FavoriteCardActionService } from '../services/form/FavoriteCardActionService';
import { ConfigFieldValue, ConfigJson } from '../config/schema/SchemaConfig';
import { RuntimeInstanceState } from '../types/runtime/RuntimeTypes';
import {
  KERNEL_SOCKET_NAME
} from '../infrastructure/bridge/kernel/KernelBridgeTypes'
import { ContinuationSocketClient } from '../infrastructure/bridge/kernel/ContinuationSocketClient'
import { CrashLogService } from '../services/crash/CrashLogService'
import { MemoryDiagnosticsService } from '../services/runtime/MemoryDiagnosticsService'
import { EntryBackgroundTaskService } from '../services/runtime/EntryBackgroundTaskService'
import { EntryAppBootstrapService } from '../services/runtime/EntryAppBootstrapService'
import { EntryRuntimeEventService } from '../services/runtime/EntryRuntimeEventService'
import { EntryKernelSocketService } from '../services/runtime/EntryKernelSocketService'
import { RemoteManageService } from '../services/remote/RemoteManageService'
import { EntryVpnConnectionService } from '../services/tun/EntryVpnConnectionService'
import { EntryVpnSetupRequestBuilder } from '../services/tun/EntryVpnSetupRequestBuilder'
import {
  RemoteConfigMeta,
  RemoteCreateDefaultConfigResult,
  RemoteGetConfigResult,
  RemoteGetFieldsResult,
  RemoteHostHandler,
  RemoteSettingsState,
  RemoteSummary
} from '../services/remote/RemoteManageTypes'
import { EntryRemoteHostDelegate, EntryRemoteHostService } from '../services/remote/EntryRemoteHostService'
import { EntryRemoteHostDomainService } from '../services/remote/EntryRemoteHostDomainService'
import {
  UPDATE_COLOR_MODE_EVENT
} from '../types/events/RuntimeEventTypes'
import { SharedIntentImportService } from '../services/share/SharedIntentImportService'
import { StatusBarIntegrationService } from '../services/desktop/StatusBarIntegrationService'

const easytier_release = easytier

@LogLocate("EntryAbility")
export default class EntryAbility extends UIAbility implements EntryRemoteHostDelegate {
  private entryVpnService: EntryVpnConnectionService | undefined = undefined
  private entryKernelSocketService: EntryKernelSocketService | undefined = undefined
  private entryBackgroundTaskService: EntryBackgroundTaskService | undefined = undefined
  private entryAppBootstrapService: EntryAppBootstrapService | undefined = undefined
  private entryRuntimeEventService: EntryRuntimeEventService | undefined = undefined
  private statusBarIntegrationService: StatusBarIntegrationService | undefined = undefined
  private mainWindow: window.Window | undefined = undefined
  private windowWillCloseCallback: (() => Promise<boolean>) | undefined = undefined
  private windowStageCloseCallback: (() => boolean) | undefined = undefined
  private continuationSocketClient: ContinuationSocketClient = new ContinuationSocketClient({
    socketName: 'easytier_vpn_socket',
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
  private remoteHostDomain: EntryRemoteHostDomainService = new EntryRemoteHostDomainService()
  private favoriteCardActions: FavoriteCardActionService = new FavoriteCardActionService()
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

  private shouldProtectProcessNet(config?: ConfigJson): boolean {
    return deviceInfo.sdkApiVersion >= 22 && AppManager.uiState.force_global && (config?.exit_nodes?.length ?? 0) > 0
  }

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
    return canIUse('SystemCapability.PCService.StatusBarManager')
  }

  private minimizeMainWindow(mainWindow: window.Window): Promise<boolean> {
    try {
      return mainWindow.minimize().then(() => {
        Logger.info('main window minimized to background', this)
        return true
      }).catch((err: BusinessError) => {
        Logger.error(`main window minimize failed: ${err.code}, ${err.message}`, this)
        return false
      })
    } catch (err) {
      Logger.error(`main window minimize error: ${JSON.stringify(err)}`, this)
      return Promise.resolve(false)
    }
  }

  private restoreMainWindow(): void {
    if (!this.mainWindow || !this.shouldMinimizeToBackground()) {
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

  private registerWindowCloseToBackground(windowStage: window.WindowStage, mainWindow: window.Window): void {
    if (!this.shouldMinimizeToBackground()) {
      return
    }
    if (deviceInfo.sdkApiVersion >= 15) {
      this.windowWillCloseCallback = () => {
        return this.minimizeMainWindow(mainWindow)
      }
      try {
        mainWindow.on('windowWillClose', this.windowWillCloseCallback)
      } catch (err) {
        Logger.debug(`windowWillClose register ignored: ${JSON.stringify(err)}`, this)
      }
    }
    if (deviceInfo.sdkApiVersion >= 14) {
      this.windowStageCloseCallback = () => {
        void this.minimizeMainWindow(mainWindow)
        return true
      }
      try {
        windowStage.on('windowStageClose', this.windowStageCloseCallback)
      } catch (err) {
        Logger.debug(`windowStageClose register ignored: ${JSON.stringify(err)}`, this)
      }
    }
  }

  startContinuousTask(cfg: string, uuid: string | undefined, name: string | undefined) {
    this.entryBackgroundTaskService?.startContinuousTask(cfg, uuid, name)
  }

  stopContinuousTask() {
    void this.entryBackgroundTaskService?.stopContinuousTask()
  }

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam) {
    this.deactivateMissionContinue();
    this.entryVpnService = new EntryVpnConnectionService({
      context: this.context,
      logTarget: this,
      requestVpnPerm: (callback: () => void) => {
        AppManager.permission.requestVpnPerm(callback)
      },
      activateMissionContinue: () => {
        this.activateMissionContinue()
      },
      setTunFd: (instanceId: string, fd: number) => {
        if (AppManager.uiState.inittedGitCore) {
          easytier.setTunFd(instanceId, fd)
          Logger.info(`setTunFd sent to git_core instance=${instanceId}`, this)
        } else {
          easytier_release.setTunFd(instanceId, fd)
          Logger.info(`setTunFd sent to release instance=${instanceId}`, this)
        }
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
    this.entryBackgroundTaskService = new EntryBackgroundTaskService({
      context: this.context,
      logTarget: this,
      runNetworkInstance: (cfg: string) => {
        return AppManager.uiState.inittedGitCore ? easytier.runNetworkInstance(cfg) : easytier_release.runNetworkInstance(cfg)
      },
      activateMissionContinue: () => {
        this.activateMissionContinue()
      },
      deactivateMissionContinue: () => {
        this.deactivateMissionContinue()
      },
      refreshFavoriteCard: () => {
        this.favoriteCardActions.refresh()
      },
      setNotificationId: (notificationId: number) => {
        AppManager.uiState.notificationId = notificationId
      },
      destroyVpnConnection: () => {
        if (this.entryVpnService) {
          return this.entryVpnService.destroyVpnConnection()
        }
        return Promise.resolve()
      },
      getBackgroundKeepAliveMode: () => {
        return AppManager.uiState.background_keep_alive_mode
      }
    })
    this.entryAppBootstrapService = new EntryAppBootstrapService({
      context: this.context,
      logTarget: this,
      syncContinuationSocket: () => {
        this.syncContinuationSocket()
      }
    })
    this.entryRuntimeEventService = new EntryRuntimeEventService({
      logTarget: this,
      syncContinuationSocket: () => {
        this.syncContinuationSocket()
      },
      prepareVpn: (shouldProtect: boolean, callback: () => void) => {
        this.entryVpnService?.prepareVpn(shouldProtect, callback)
      },
      shouldProtectProcessNet: (config?: ConfigJson) => {
        return this.shouldProtectProcessNet(config)
      },
      getKernelSocketPath: () => {
        return AppManager.uiState.getSocketPath(KERNEL_SOCKET_NAME)
      },
      connectToKernelSocket: (socketPath: string) => {
        this.entryKernelSocketService?.connect(socketPath)
      },
      startContinuousTask: (cfg: string, uuid: string | undefined, name: string | undefined) => {
        this.startContinuousTask(cfg, uuid, name)
      },
      stopContinuousTask: () => {
        this.stopContinuousTask()
      },
      closeKernelSocket: () => {
        this.entryKernelSocketService?.close()
      },
      buildTunSetupRequest: (data: emitter.EventData) => {
        return this.vpnSetupRequestBuilder.buildFromEventData(data)
      },
      setupTun: (request) => {
        void this.entryVpnService?.setupTun(request)
      }
    })
    this.statusBarIntegrationService = new StatusBarIntegrationService(this.context, this, () => {
      this.restoreMainWindow()
    })
    RemoteManageService.setHostHandlerProvider(() => this.createRemoteHostHandler())
    this.favoriteCardActions.start(this.callee)
    CrashLogService.init(this.context.filesDir)
    easytier.initLogManager(this.context.filesDir, 'ui')
    easytier.configureLogManager(false, false)
    this.entryRuntimeEventService.start()
    HMRouterMgr.openLog("INFO")
    HMRouterMgr.init({
      context: this.context
    })
    Logger.info("BuildTime:" + BUILD_TIME, this)
    WindowUtil.colorMode = this.context.config.colorMode ?? -1
    this.appReadyPromise = this.initApp()
    this.appReadyPromise.then(() => {
      this.statusBarIntegrationService?.start().catch((error: Error) => {
        Logger.error(`status bar integration start failed: ${JSON.stringify(error)}`, this)
      })
      this.readSharedData(want)
      this.favoriteCardActions.refresh()
      if (launchParam.launchReason === AbilityConstant.LaunchReason.CONTINUATION) {
        if (want.parameters !== undefined) {
          let url = want.parameters.data as string
          this.readUri(url)
        }
      }
      if (AppManager.uiState.inittedGitCore) {
        easytier.initPanicHook()
      }else {
        easytier_release.initPanicHook()
      }
    })
  }

  onCollaborate(wantParam: Record<string, Object>): AbilityConstant.CollaborateResult {
    Logger.info("onCollaborate", this)
    const result = RemoteManageService.handleCollaborate(this.context, wantParam)
    return result === 0 ? AbilityConstant.CollaborateResult.ACCEPT : AbilityConstant.CollaborateResult.REJECT
  }

  private createRemoteHostHandler(): RemoteHostHandler {
    return EntryRemoteHostService.createHandler(this)
  }

  remoteWaitReady(): Promise<void> {
    return this.appReadyPromise
  }

  remoteManageConnected(): void {
  }

  remoteManageDisconnected(): void {
  }

  remoteConfigList(): RemoteConfigMeta[] {
    return this.remoteHostDomain.remoteConfigList()
  }

  remoteSettings(): RemoteSettingsState {
    return this.remoteHostDomain.remoteSettings()
  }

  remoteSummary(): RemoteSummary {
    return this.remoteHostDomain.remoteSummary()
  }

  remoteGetConfig(configId: string): RemoteGetConfigResult | undefined {
    return this.remoteHostDomain.remoteGetConfig(configId)
  }

  remoteGetRuntimeInstance(configId: string): RuntimeInstanceState | undefined {
    return this.remoteHostDomain.remoteGetRuntimeInstance(configId)
  }

  remoteGetConfigFields(configId: string, fields: string[]): RemoteGetFieldsResult {
    return this.remoteHostDomain.remoteGetConfigFields(configId, fields)
  }

  remoteSetConfigField(configId: string, field: string, value: ConfigFieldValue): boolean {
    return this.remoteHostDomain.remoteSetConfigField(configId, field, value)
  }

  remoteSaveConfig(configId: string, displayName: string, config: ConfigJson): boolean {
    return this.remoteHostDomain.remoteSaveConfig(configId, displayName, config)
  }

  remoteCreateDefaultConfig(displayName: string): RemoteCreateDefaultConfigResult | undefined {
    return this.remoteHostDomain.remoteCreateDefaultConfig(displayName)
  }

  remoteImportConfig(config: ConfigJson, displayName: string): RemoteCreateDefaultConfigResult | undefined {
    return this.remoteHostDomain.remoteImportConfig(config, displayName)
  }

  remoteDeleteConfig(configId: string): boolean {
    return this.remoteHostDomain.remoteDeleteConfig(configId)
  }

  remoteRenameConfig(configId: string, displayName: string): boolean {
    return this.remoteHostDomain.remoteRenameConfig(configId, displayName)
  }

  remoteSetSetting(key: string, value: boolean | string): RemoteSettingsState {
    return this.remoteHostDomain.remoteSetSetting(key, value)
  }

  async remoteRequestPermission(kind: string): Promise<RemoteSettingsState> {
    return this.remoteHostDomain.remoteRequestPermission(kind)
  }

  async initApp() {
    await this.entryAppBootstrapService?.initialize()
  }

  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam) {
    Logger.debug("onNetWant", this)
    this.restoreMainWindow()
    this.readSharedData(want)
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
	    MemoryDiagnosticsService.enableSystemLeakWatcher(false)
	    RemoteManageService.destroyHostSessions()
    AppManager.easytier.destroy()
    this.entryRuntimeEventService?.stop()
    this.stopContinuousTask()
    this.entryKernelSocketService?.close()
    this.continuationSocketClient.close()
    this.statusBarIntegrationService?.close()
    this.favoriteCardActions.stop()
  }

  async onContinue(wantParam: Record<string, Object>): Promise<AbilityConstant.OnContinueResult> {
    if (AppManager.easytier.runningNetworks.size > 0) {
      let uuid = AppManager.easytier.runningNetworks.keys().next().value as string
      let cfg: ConfigJson | undefined = AppManager.easytier.getConfig(uuid)
      Logger.debug("find "+JSON.stringify(cfg))
      if (cfg) {
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
    try {
      const mainWindow = windowStage.getMainWindowSync()
      this.mainWindow = mainWindow
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
    } catch (error) {
    }
    windowStage.loadContent('pages/HMRouterIndex', (err) => {
      if (err.code) {
        Logger.error('Failed to load the content. Cause: ' + JSON.stringify(err), this);
        return;
      }
      windowStage.getMainWindow().then((win) => {
        win.setWindowKeepScreenOn(true)
      })
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
    this.syncContinuationSocket()
    this.statusBarIntegrationService?.broadcastState()
  }

  onBackground(): void {
    WindowUtil.background()
  }

  onConfigurationUpdate(newConfig: Configuration): void {
    WindowUtil.colorMode = newConfig.colorMode ?? -1
    EventHelper.emitterPublish(UPDATE_COLOR_MODE_EVENT)
  }

}
