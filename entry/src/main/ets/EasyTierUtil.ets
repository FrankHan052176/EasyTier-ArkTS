import entry from 'libentry.so'
import easytier from 'easytier-ohrs'
import { EventHelper } from './util/EventHelper'
import { AppManager } from './AppManager'
import { Logger, LogLocate } from './shared/logging/Logger'
import { sendToast } from './ToastUtil'
import { InstanceInfo } from './class/InstanceInfo'
import { deviceInfo } from '@kit.BasicServicesKit'
import { getDefaultConfig } from './config/defaults/ConfigDefaults'
import { JSON, taskpool } from '@kit.ArkTS'
import { LogDataSource } from './class/data_source/LogDataSource'
import { updateFavorite } from './services/form/CommunicationUtil'
import { HMRouterMgr } from '@hadss/hmrouter'
import { updateTextNotification } from './util/NoticeHelper'
import { fileIo, fileUri } from '@kit.CoreFileKit'
import { systemShare } from '@kit.ShareKit'
import { common, Want } from '@kit.AbilityKit'
import { uniformTypeDescriptor } from '@kit.ArkData'
import { socket, vpnExtension } from '@kit.NetworkKit'
import { syncWholeConfig } from './ConfigSyncUtil'
import { ConfigJson } from './config/schema/SchemaConfig'
import { RuntimeAggregateState, RuntimeInstanceState } from './types/runtime/RuntimeTypes'
import { VpnLogData } from './infrastructure/bridge/kernel/KernelBridgeTypes'
import { routeSignature } from './infrastructure/bridge/kernel/RouteStore'
import { getEditingConfig as getEditingStoredConfig, getStoredConfig, getStoredConfigLabel, getStoredConfigName, listStoredConfigs as listStoredConfigEntries, StoredConfigMetaLite } from './services/config/storage/StoredConfigService'
import { connectVpnExtensionSocket } from './infrastructure/bridge/kernel/VpnExtensionSocketBridge'
import { orchestrateInstanceStart } from './services/easytier/runtime/StartOrchestrationService'


@Concurrent
async function readLogsWorker(): Promise<void> {
  setInterval(() => {
    let appLogs = entry.getAppLog()
    let nmLogs = entry.getNetworkManagerLog()
    EventHelper.emitterPublish("worker_readLogs", {
      data: {
        appLogs: appLogs,
        nmLogs: nmLogs
      }
    })
  }, 100)
}

@LogLocate("EasyTierUtil")
@ObservedV2
export class EasyTierUtil {
  @Trace appLogs: LogDataSource = new LogDataSource
  @Trace nmLogs: LogDataSource = new LogDataSource
  @Trace ohLogs: LogDataSource = new LogDataSource
  @Trace runningNetworks: Map<string, RuntimeInstanceState> = new Map()
  @Trace instanceInfos: Map<string, InstanceInfo> = new Map()
  @Trace needTUN: Set<string> = new Set()
  task2: taskpool.LongTask | undefined
  client: socket.LocalSocket | undefined
  vpnMessageBuffer: string = ''
  private isVpnConnected: boolean = false

  init() {
    EventHelper.emitterListener("worker_readLogs", (event) => {
      if (event?.data) {
        this.processLogs(event.data.appLogs as string[], event.data.nmLogs as string[])
      }
    })
    EventHelper.emitterListener("kernel_runtime_snapshot", (event) => {
      if (event?.data?.snapshot) {
        this.processRuntimeSnapshot(event.data.snapshot as RuntimeAggregateState, false)
      }
    })

    this.task2 = new taskpool.LongTask(readLogsWorker)
    taskpool.execute(this.task2)

    if (AppManager.uiState.ext_mode) {
      this.connectToVpnExtension("easytier_vpn_socket")
    }
  }

  destroy() {
    taskpool.terminateTask(this.task2)
    this.client?.close()
  }

  version() {
    return easytier.easytierVersion()
  }

  convertToml2NetworkConfig(toml: string): string {
    return easytier.convertTomlToNetworkConfig(toml)
  }

  private updateNotification(uuid: string) {
    let info = AppManager.easytier.instanceInfos.get(uuid)
    if (info) {
      updateTextNotification(this.getConfigName(uuid) ?? "N/A", info)
    }
  }

  private getValidInstanceId(instance: RuntimeInstanceState): string | undefined {
    const instanceId = instance.instanceId
    if (typeof instanceId !== 'string' || instanceId.length === 0) {
      return undefined
    }
    return instanceId
  }

  private processRuntimeSnapshot(snapshot: RuntimeAggregateState, fromVpn: boolean = true): void {
    if (!fromVpn && AppManager.uiState.ext_mode && this.isVpnConnected) {
      return
    }

    const instances = snapshot.instances ?? []
    Logger.debug(`processRuntimeSnapshot fromVpn=${fromVpn} extMode=${AppManager.uiState.ext_mode} instances=${instances.length}`, this)
    const activeIds = new Set<string>()
    instances.forEach((instance) => {
      const instanceId = this.getValidInstanceId(instance)
      if (!instanceId) {
        Logger.error(`processRuntimeSnapshot skip invalid instanceId: ${JSON.stringify(instance)}`, this)
        return
      }
      activeIds.add(instanceId)
      if (!(instance.running as boolean)) {
        return
      }
      this.runningNetworks.set(instanceId, instance)
      if (!this.instanceInfos.has(instanceId)) {
        this.instanceInfos.set(instanceId, new InstanceInfo())
      }
      this.instanceInfos.get(instanceId)?.update(instance)
      this.updateNotification(instanceId)
    })

    for (const uuid of Array.from(this.runningNetworks.keys())) {
      if (!activeIds.has(uuid)) {
        this.runningNetworks.delete(uuid)
        this.instanceInfos.delete(uuid)
        this.needTUN.delete(uuid)
      }
    }

  }

  processLogs(appLogs: string[], nmLogs: string[]) {
    appLogs.forEach((value) => {
      this.appLogs.add(value)
    })
    nmLogs.forEach((value) => {
      this.nmLogs.add(value)
    })
  }

  private connectToVpnExtension(socketName: string) {
    this.client = connectVpnExtensionSocket(socketName, this.client, {
      isExtMode: () => AppManager.uiState.ext_mode,
      getSocketPath: (name: string) => AppManager.uiState.getSocketPath(name),
      onConnected: () => {
        this.isVpnConnected = true
      },
      onDisconnected: () => {
        this.isVpnConnected = false
      },
      onSnapshot: (snapshot: RuntimeAggregateState) => {
        Logger.debug(`VpnExtension runtime_snapshot received instances=${snapshot.instances?.length ?? 0}`, this)
        this.processRuntimeSnapshot(snapshot, true)
      },
      onLogs: (logData: VpnLogData) => {
        this.processLogs(logData.appLogs, logData.nmLogs)
      }
    })
  }

  public start(uuid: string | undefined = AppManager.uiState.selected, byCard: boolean = false): boolean {
    if (uuid) {
      let config: ConfigJson | undefined = this.getConfig(uuid)
      if (config) {
        Logger.debug("start config: "+ JSON.stringify(config, undefined, 2), this)
        syncWholeConfig(uuid, this.getConfigName(uuid) ?? uuid, config)
        if (easytier.parseNetworkConfig(JSON.stringify(config))) {
          if (!config.no_tun) {
            this.needTUN.add(uuid)
          }
          if (AppManager.uiState.ext_mode) {
            let want: Want = {
              bundleName: "top.frankhan.easytier",
              abilityName: "EasyTierAbility",
              parameters: {
                cfg: JSON.stringify(config),
                name: this.getConfigName(uuid) ?? "",
                socket: "easytier_vpn_socket",
                socket_files_dir: AppManager.uiState.socketFilesDir,
                vpn_routes: AppManager.uiState.vpn_routes,
                white_list: AppManager.uiState.white_list,
                black_list: AppManager.preference.getBlackList(),
                dns: AppManager.uiState.dns,
                dev: AppManager.uiState.dev,
                force_global: AppManager.uiState.force_global,
                show_log: AppManager.uiState.show_log
              }
            }
            vpnExtension.startVpnExtensionAbility(want)
            this.connectToVpnExtension("easytier_vpn_socket")
          } else {
            AppManager.permission.requestLocPerm().then(() => {
              EventHelper.emitterPublish("start_bg", {
                data: {
                  cfg: JSON.stringify(config),
                  uuid: byCard?undefined:uuid,
                  name: this.getConfigName(uuid)
                }
              })
            })
          }
        } else {
          sendToast("非法实例, 可能是序列化错误, 请上报日志.", $r("sys.symbol.exclamationmark_circle"), 1)
        }
        return true
      } else {
        return false
      }
    } else {
      return false
    }
  }

  public temp_start(name: string, config: ConfigJson): boolean {
    if (config) {
      Logger.debug("temp start config: "+ JSON.stringify(config, undefined, 2), this)
      syncWholeConfig(config.instance_id!, name, config)
      return orchestrateInstanceStart({
        config,
        name,
        extMode: AppManager.uiState.ext_mode,
        socketFilesDir: AppManager.uiState.socketFilesDir,
        vpnRoutes: AppManager.uiState.vpn_routes,
        whiteList: AppManager.uiState.white_list,
        blackList: AppManager.preference.getBlackList(),
        dns: AppManager.uiState.dns,
        dev: AppManager.uiState.dev,
        forceGlobal: AppManager.uiState.force_global,
        showLog: AppManager.uiState.show_log,
        addNeedTun: (instanceId: string) => {
          this.needTUN.add(instanceId)
        },
        connectToVpnExtension: (socketName: string) => {
          this.connectToVpnExtension(socketName)
        },
        requestLocPerm: () => AppManager.permission.requestLocPerm(),
        publishStartBg: (cfg: string, uuid: string | undefined, startName: string) => {
          EventHelper.emitterPublish("start_bg", {
            data: {
              cfg,
              uuid,
              name: startName
            }
          })
        },
        sendInvalidConfigToast: () => {
          sendToast("非法实例, 可能是序列化错误, 请上报日志.", $r("sys.symbol.exclamationmark_circle"), 1)
        }
      })
    } else {
      return false
    }
  }

  public stop() {
    if (AppManager.uiState.ext_mode) {
      let want: Want = {
        bundleName: "top.frankhan.easytier",
        abilityName: "EasyTierAbility",
      }
      vpnExtension.stopVpnExtensionAbility(want)
      this.client?.close()
      this.client = undefined
      this.isVpnConnected = false
    } else {
      const runningIds = Array.from(this.runningNetworks.keys()).filter((value) => {
        return value.length > 0
      }) as string[]
      EventHelper.emitterPublish("stop_bg")
      runningIds.forEach((value) => {
        easytier.stopKernel(value)
      })
    }

    // 显式清理 UI 状态
    this.runningNetworks.clear()
    this.instanceInfos.clear()

    setTimeout(() => {
      updateFavorite()
    }, 100)
    let stack = HMRouterMgr.getPathStack("MainNavigation")!.getAllPathName()
    if (stack[stack.length-1] == "StatusPage") {
      HMRouterMgr.pop()
    }
  }

  public isRunning(uuid?: string): boolean {
    if (uuid) {
      return this.runningNetworks.has(uuid)
    }
    return false
  }

  public getConfig(uuid: string): ConfigJson | undefined {
    return getStoredConfig(uuid)
  }

  public getEditingConfig(): ConfigJson | undefined {
    return getEditingStoredConfig(AppManager.uiState.editingInstance)
  }

  public getConfigName(uuid: string | undefined): string | undefined {
    return getStoredConfigName(uuid)
  }

  public getConfigLabel(uuid: string | undefined, emptyLabel: string = ''): string {
    return getStoredConfigLabel(uuid, emptyLabel)
  }

  public listStoredConfigs(): StoredConfigMetaLite[] {
    return listStoredConfigEntries()
  }

  public getEditingInstance() {
    return AppManager.uiState.editingInstance
  }

  public isEditingRunning(): boolean {
    return this.isRunning(this.getEditingInstance())
  }

  public isFavoritesRunning(): boolean {
    return this.isRunning(AppManager.uiState.favorite)
  }

  public writeAndShareLogs() {
    let filePath = AppManager.content.context!.filesDir + '/log.txt';
    let file: fileIo.File | null = null;
    try {
      fileIo.unlinkSync(filePath)
    }catch (_) {}
    try {
      file = fileIo.openSync(filePath, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE);
      fileIo.writeSync(file.fd, this.appLogs.join2String());
      fileIo.closeSync(file);

      let shareData: systemShare.SharedData = new systemShare.SharedData({
        utd: uniformTypeDescriptor.UniformDataType.FILE,
        uri: fileUri.getUriFromPath(filePath),
        title: '分享日志'
      });
      let controller: systemShare.ShareController = new systemShare.ShareController(shareData);
      controller.show(AppManager.content.context! as common.UIAbilityContext, {
        selectionMode: systemShare.SelectionMode.SINGLE,
        previewMode: systemShare.SharePreviewMode.DEFAULT,
        excludedAbilities: [systemShare.ShareAbilityType.PRINT,
          systemShare.ShareAbilityType.SAVE_TO_SUPERHUB]
      }).catch(() => {
        Logger.error(`systemShareConfig::An unexpected error occurred.`, this);
      })
    } catch (err) {
      Logger.error(`日志文件写入失败. Code: ${err.code}, message: ${err.message}`, this)
    }
  }
}
