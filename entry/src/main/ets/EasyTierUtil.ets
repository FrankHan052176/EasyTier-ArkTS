import entry from 'libentry.so'
import easytier from 'easytier-ohrs'
import { EventHelper } from './util/EventHelper'
import { AppManager } from './AppManager'
import { Logger, LogLocate } from './util/Logger'
import { sendToast } from './ToastUtil'
import { InstanceInfo } from './class/InstanceInfo'
import { NetworkSegment } from './class/NetworkSegment'
import { SafeSet } from './util/SafeSet'
import { deviceInfo } from '@kit.BasicServicesKit'
import { getDefaultConfig } from './ConfigDefaults'
import { buffer, JSON, taskpool, util } from '@kit.ArkTS'
import { LogDataSource } from './class/data_source/LogDataSource'
import { updateFavorite } from './CommunicationUtil'
import { HMRouterMgr } from '@hadss/hmrouter'
import { updateTextNotification } from './util/NoticeHelper'
import { fileIo, fileUri } from '@kit.CoreFileKit'
import { systemShare } from '@kit.ShareKit'
import { common, Want } from '@kit.AbilityKit'
import { uniformTypeDescriptor } from '@kit.ArkData'
import { socket, vpnExtension } from '@kit.NetworkKit'
import { syncWholeConfig } from './ConfigSyncUtil'
import { ConfigJson } from './SchemaConfig'
import { RuntimeAggregateState, RuntimeInstanceState } from './RuntimeTypes'

const easytier_release = easytier

interface StoredConfigMetaLite {
  configId: string
  displayName: string
}

@Concurrent
async function readLogsWorker(): Promise<void> {
  setInterval(() => {
    let appLogs = entry.getAppLog()
    let nmLogs = entry.getNetworkManagerLog()
    let ohLogs = entry.getOHLog()
    EventHelper.emitterPublish("worker_readLogs", {
      data: {
        appLogs: appLogs,
        nmLogs: nmLogs,
        ohLogs: ohLogs
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
  task1: taskpool.LongTask | undefined
  task2: taskpool.LongTask | undefined
  tunRoutes: SafeSet<NetworkSegment> = new SafeSet()
  client: socket.LocalSocket | undefined
  private isVpnConnected: boolean = false
  private lastKernelRoutesSignature: string = ''

  init() {
    EventHelper.emitterListener("worker_readLogs", (event) => {
      if (event?.data) {
        this.processLogs(event.data.appLogs as string[], event.data.nmLogs as string[], event.data.ohLogs as string[], false)
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
    taskpool.terminateTask(this.task1)
    taskpool.terminateTask(this.task2)
    this.client?.close()
  }

  version() {
    if (AppManager.uiState.git_core) {
      return easytier.easytierVersion()
    }else {
      return easytier_release.easytierVersion()
    }
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
    const activeIds = new Set<string>()
    instances.forEach((instance) => {
      const instanceId = this.getValidInstanceId(instance)
      if (!instanceId) {
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

    if (!AppManager.uiState.ext_mode) {
      const tun = snapshot.tun
      const aggregatedRoutes = tun?.aggregatedRoutes ?? []
      const routeSignature = JSON.stringify(aggregatedRoutes)
      if (!tun?.active) {
        this.lastKernelRoutesSignature = ''
        return
      }
      if (routeSignature !== this.lastKernelRoutesSignature) {
        this.lastKernelRoutesSignature = routeSignature
        this.tunRoutes.clear()
        aggregatedRoutes.forEach((route: string): void => {
          try {
            this.tunRoutes.add(new NetworkSegment(route))
          } catch (_) {
          }
        })
        let firstAttached: RuntimeInstanceState | undefined = undefined
        for (const instance of (snapshot.instances ?? [])) {
          const instanceId = this.getValidInstanceId(instance)
          if (instanceId && (tun.attachedInstanceIds ?? []).includes(instanceId) && !!instance.myNodeInfo?.virtualIpv4Cidr) {
            firstAttached = instance
            break
          }
        }
        const cidr = firstAttached?.myNodeInfo?.virtualIpv4Cidr
        const ip = firstAttached?.myNodeInfo?.virtualIpv4
        if (cidr && ip) {
          const mask = Number(cidr.split('/')[1] ?? '24')
          EventHelper.emitterPublish("update_route", {
            data: {
              ip,
              mask,
              id: firstAttached?.instanceId,
              magicDNS: firstAttached?.magicDnsEnabled ?? false,
              needExitNode: firstAttached?.needExitNode ?? false,
              routes: aggregatedRoutes
            }
          })
        }
      }
    }
  }

  processLogs(appLogs: string[], nmLogs: string[], ohLogs: string[], fromVpn: boolean = true) {
    appLogs.forEach((value) => {
      this.appLogs.add(value)
    })
    nmLogs.forEach((value) => {
      this.nmLogs.add(value)
    })
    ohLogs.forEach((value) => {
      this.ohLogs.add(value)
    })
  }

  private connectToVpnExtension(socketName: string) {
    this.client?.close()
    this.client = socket.constructLocalSocketInstance()
    let address: socket.LocalConnectOptions = {
      address: {
        address: AppManager.content.context!.filesDir + '/' + socketName
      }
    }

    let retryCount = 0
    let connect = () => {
      if (!AppManager.uiState.ext_mode) return;
      this.client?.connect(address).then(() => {
        Logger.info("Connected to VpnExtension socket", this)
        this.isVpnConnected = true
      }).catch((err: object) => {
        this.isVpnConnected = false
        if (retryCount < 10 && AppManager.uiState.ext_mode) {
          retryCount++
          setTimeout(connect, 500)
        }
      })
    }
    setTimeout(connect, 200)

    this.client!.on('message', (value: socket.LocalSocketMessageInfo) => {
      try {
        let str = buffer.from(value.message).toString();
        let msg: ESObject = JSON.parse(str);
        if (msg.type === "runtime_snapshot") {
          this.processRuntimeSnapshot(msg.data as RuntimeAggregateState, true)
        } else if (msg.type === "logs") {
          let logData: ESObject = msg.data;
          this.processLogs(logData.appLogs as string[], logData.nmLogs as string[], logData.ohLogs as string[], true)
        }
      } catch (e) {
        Logger.error("Failed to process VpnExtension message: " + JSON.stringify(e), this)
      }
    })

    this.client!.on('close', () => {
      this.isVpnConnected = false
    })
  }

  public start(uuid: string | undefined = AppManager.uiState.selected, byCard: boolean = false): boolean {
    if (uuid) {
      let config: ConfigJson | undefined = this.getConfig(uuid)
      if (config) {
        Logger.debug("start config: "+ JSON.stringify(config, undefined, 2), this)
        syncWholeConfig(uuid, this.getConfigName(uuid) ?? uuid, config)
        if (AppManager.uiState.git_core?easytier.parseNetworkConfig(JSON.stringify(config)):easytier_release.parseNetworkConfig(JSON.stringify(config))) {
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
                git_core: AppManager.uiState.git_core,
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
      if (AppManager.uiState.git_core?easytier.parseNetworkConfig(JSON.stringify(config)):easytier_release.parseNetworkConfig(JSON.stringify(config))) {
        if (!config.no_tun) {
          this.needTUN.add(config.instance_id!)
        }
        if (AppManager.uiState.ext_mode) {
          let want: Want = {
            bundleName: "top.frankhan.easytier",
            abilityName: "EasyTierAbility",
            parameters: {
              cfg: JSON.stringify(config),
              name: name,
              socket: "easytier_vpn_socket",
              git_core: AppManager.uiState.git_core,
              vpn_routes: AppManager.uiState.vpn_routes,
              white_list: AppManager.uiState.white_list,
              black_list: AppManager.preference.getBlackList(),
              dns: AppManager.uiState.dns,
              dev: AppManager.uiState.dev,
              force_global: AppManager.uiState.force_global,
              show_log: AppManager.uiState.show_log
            }            }
          vpnExtension.startVpnExtensionAbility(want)
          this.connectToVpnExtension("easytier_vpn_socket")
        } else {
          AppManager.permission.requestLocPerm().then(() => {
            EventHelper.emitterPublish("start_bg", {
              data: {
                cfg: JSON.stringify(config),
                uuid: config.instance_id,
                name: name
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
      if (AppManager.uiState.git_core) {
        runningIds.forEach((value) => {
          easytier.stopKernel(value)
        })
      } else if (runningIds.length > 0) {
        easytier_release.stopNetworkInstance(runningIds)
      }
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
    const rawConfig = easytier.getConfig(uuid)
    if (!rawConfig) {
      return undefined
    }
    try {
      const rawConfigJson: string = rawConfig
      return JSON.parse(rawConfigJson) as ConfigJson
    } catch (_) {
      return undefined
    }
  }

  public getEditingConfig(): ConfigJson | undefined {
    const editingId = AppManager.uiState.editingInstance
    return editingId ? (this.getConfig(editingId) ?? getDefaultConfig("")) : getDefaultConfig("")
  }

  public getConfigName(uuid: string | undefined): string | undefined {
    if (!uuid || uuid.length === 0) {
      return undefined
    }
    return easytier.getConfigDisplayNameById(uuid) ?? undefined
  }

  public getConfigLabel(uuid: string | undefined, emptyLabel: string = ''): string {
    if (!uuid || uuid.length === 0) {
      return emptyLabel
    }
    const name = this.getConfigName(uuid)
    return name && name.length > 0 ? name : uuid
  }

  public listStoredConfigs(): StoredConfigMetaLite[] {
    try {
      const rawEntries = JSON.parse(easytier.listConfigs()) as StoredConfigMetaLite[]
      return (rawEntries ?? []).map((item) => {
        const configId = item.configId
        const displayName = item.displayName ?? configId
        const entry: StoredConfigMetaLite = { configId, displayName }
        return entry
      }).filter((item) => item.configId.length > 0)
    } catch (_) {
      return []
    }
  }

  public getAllConfigIds(): string[] {
    return AppManager.data.configIds
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

  private addTunRoutes(route: string): boolean {
    let result = true
    this.tunRoutes.forEach((oldRoute) => {
      result = !oldRoute.contains(route) && result
    })
    if (result) {
      try {
        this.tunRoutes.add(new NetworkSegment(route))
      } catch (e) {
        Logger.error("[" + route + "] 是非法路由.", this)
        return false
      }
    }
    return result
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
