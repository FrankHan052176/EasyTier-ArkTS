import entry from 'libentry.so'
import { NetworkConfig, NetworkInstanceRunningInfo } from './protobuf/api_manage'
import easytier, { KeyValuePair } from 'easytier-ohrs'
import { EventHelper } from './util/EventHelper'
import { AppManager } from './AppManager'
import { Logger, LogLocate } from './util/Logger'
import { sendToast } from './ToastUtil'
import { InstanceInfo } from './class/InstanceInfo'
import { convertAddrToIp } from './util/Conversion'
import { NetworkSegment } from './class/NetworkSegment'
import { SafeSet } from './util/SafeSet'
import { deviceInfo } from '@kit.BasicServicesKit'
import { ContentUtil } from './ContentUtil'
import { JSON, taskpool } from '@kit.ArkTS'
import { LogDataSource } from './class/data_source/LogDataSource'
import { updateFavorite } from './CommunicationUtil'
import { HMRouterMgr } from '@hadss/hmrouter'
import { updateTextNotification } from './util/NoticeHelper'
import easytier_release from 'easytier-release'
import { fileIo, fileUri } from '@kit.CoreFileKit'
import { systemShare } from '@kit.ShareKit'
import { common } from '@kit.AbilityKit'
import { uniformTypeDescriptor } from '@kit.ArkData'

@Concurrent
async function readInfoWorker(git_core: boolean): Promise<void> {
  setInterval(() => {
    let infos = git_core?easytier.collectNetworkInfos():easytier_release.collectNetworkInfos()
    EventHelper.emitterPublish("worker_readInfo", {
      data: {
        infos: infos
      }
    })
  }, 100)
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
  @Trace runningNetworks: Map<string, NetworkInstanceRunningInfo> = new Map()
  @Trace instanceInfos: Map<string, InstanceInfo> = new Map()
  @Trace needTUN: Set<string> = new Set()
  task1: taskpool.LongTask | undefined
  task2: taskpool.LongTask | undefined
  tunRoutes: SafeSet<NetworkSegment> = new SafeSet()

  init() {
    EventHelper.emitterListener("worker_readInfo", (event) => {
      if (event?.data?.infos) {
        this.processNetworkInfos(event.data.infos)
      }
    })
    EventHelper.emitterListener("worker_readLogs", (event) => {
      if (event?.data) {
        this.processLogs(event.data.appLogs, event.data.nmLogs, event.data.ohLogs)
      }
    })
    this.task1 = new taskpool.LongTask(readInfoWorker, AppManager.preference.inittedGitCore)
    this.task2 = new taskpool.LongTask(readLogsWorker)
    taskpool.execute(this.task1)
    taskpool.execute(this.task2)
  }

  destroy() {
    taskpool.terminateTask(this.task1)
    taskpool.terminateTask(this.task2)
  }

  version() {
    if (AppManager.preference.inittedGitCore) {
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
      updateTextNotification(AppManager.uiState.configUUIDNameMap.get(uuid) ?? "N/A", info)
    }
  }

  processNetworkInfos(infos: KeyValuePair[]) {
    let networks = new Set<string>()
    for (const info of infos) {
      networks.add(info.key)
      let newInfo: NetworkInstanceRunningInfo
      try {
        newInfo = JSON.parse(info.value) as NetworkInstanceRunningInfo
      } catch (e) {
        Logger.error(`processNetworkInfos parse error: ${JSON.stringify(e)}`, this)
        continue
      }
      if (!newInfo.running) {
        Logger.error("ReadErrorInfo: " + newInfo.error_msg, this)
        this.stop()
        continue
      }
      this.runningNetworks.set(info.key, newInfo)
      if (!this.instanceInfos.has(info.key)) {
        this.instanceInfos.set(info.key, new InstanceInfo())
      }
      this.instanceInfos.get(info.key)?.update(newInfo)
      this.updateNotification(info.key)
      if (this.needTUN.has(info.key) && newInfo.my_node_info?.virtual_ipv4 &&
        newInfo.my_node_info?.virtual_ipv4?.address) {
        this.needTUN.delete(info.key)
        let config = AppManager.data.configUUIDMap.get(info.key) ?? AppManager.data.tempConfigMap.get(info.key)!
        config.routes.forEach((route) => {
          this.tunRoutes.add(new NetworkSegment(route.toString()))
        })
        this.tunRoutes.add(new NetworkSegment(convertAddrToIp(newInfo.my_node_info.virtual_ipv4.address.addr) + "/" +
        newInfo.my_node_info.virtual_ipv4.network_length))
        newInfo.routes.forEach((route) => {
          route.proxy_cidrs.forEach((cidr) => {
            this.addTunRoutes(cidr)
          })
          if (route.ipv4_addr?.address) {
            this.addTunRoutes(convertAddrToIp(route.ipv4_addr.address.addr) + "/" + route.ipv4_addr.network_length)
          }
        })
        EventHelper.emitterPublish("setup_tun", {
          data: {
            ip: convertAddrToIp(newInfo.my_node_info.virtual_ipv4.address.addr),
            mask: newInfo.my_node_info.virtual_ipv4.network_length,
            id: info.key,
            magicDNS: config!.enable_magic_dns ?? false,
            needExitNode: config!.exit_nodes.length > 0
          }
        })
        AppManager.data.tempConfigMap.delete(info.key)
      }
      if (!this.needTUN.has(info.key) && (AppManager.preference.vpn_routes || deviceInfo.sdkApiVersion >= 20)) {
        let needUpdate = false
        newInfo.routes.forEach((route) => {
          route.proxy_cidrs.forEach((cidr) => {
            needUpdate = this.addTunRoutes(cidr) || needUpdate
          })
          if (route.ipv4_addr?.address) {
            needUpdate = needUpdate ||
            this.addTunRoutes(convertAddrToIp(route.ipv4_addr.address.addr) + "/" + route.ipv4_addr.network_length)
          }
        })
        if (needUpdate && newInfo.my_node_info?.virtual_ipv4?.address) {
          EventHelper.emitterPublish("update_route", {
            data: {
              ip: convertAddrToIp(newInfo.my_node_info.virtual_ipv4.address.addr),
              mask: newInfo.my_node_info.virtual_ipv4.network_length,
              id: info.key,
              magicDNS: AppManager.data.configUUIDMap.get(info.key)?.enable_magic_dns ?? false,
              needExitNode: (AppManager.data.configUUIDMap.get(info.key)?.exit_nodes ?? []).length > 0
            }
          })
        }
      }
    }
    for (const uuid of Array.from(this.runningNetworks.keys())) {
      if (!networks.has(uuid)) {
        this.runningNetworks.delete(uuid)
        this.instanceInfos.delete(uuid)
      }
    }
  }

  processLogs(appLogs: string[], nmLogs: string[], ohLogs: string[]) {
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

  public start(uuid: string | undefined = AppManager.uiState.selected, byCard: boolean = false): boolean {
    if (uuid) {
      let config = AppManager.data.configUUIDMap.get(uuid)
      if (config) {
        Logger.debug("start config: "+ JSON.stringify(config, undefined, 2), this)
        if (AppManager.preference.inittedGitCore?easytier.parseNetworkConfig(JSON.stringify(config)):easytier_release.parseNetworkConfig(JSON.stringify(config))) {
          if (!config.no_tun) {
            this.needTUN.add(uuid)
          }
          AppManager.permission.requestLocPerm().then(() => {
            EventHelper.emitterPublish("start_bg", {
              data: {
                cfg: JSON.stringify(config),
                uuid: byCard?undefined:uuid,
                name: AppManager.uiState.configUUIDNameMap.get(uuid)
              }
            })
          })
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

  public temp_start(name: string, config: NetworkConfig): boolean {
    if (config) {
      Logger.debug("temp start config: "+ JSON.stringify(config, undefined, 2), this)
      if (AppManager.preference.inittedGitCore?easytier.parseNetworkConfig(JSON.stringify(config)):easytier_release.parseNetworkConfig(JSON.stringify(config))) {
        if (!config.no_tun) {
          this.needTUN.add(config.instance_id!)
        }
        AppManager.permission.requestLocPerm().then(() => {
          EventHelper.emitterPublish("start_bg", {
            data: {
              cfg: JSON.stringify(config),
              uuid: config.instance_id,
              name: name
            }
          })
        })
      } else {
        sendToast("非法实例, 可能是序列化错误, 请上报日志.", $r("sys.symbol.exclamationmark_circle"), 1)
      }
      return true
    } else {
      return false
    }
  }

  public stop() {
    EventHelper.emitterPublish("stop_bg")
    if (AppManager.preference.inittedGitCore) {
      easytier.stopNetworkInstance(Array.from(this.runningNetworks.keys()))
    }else {
      easytier_release.stopNetworkInstance(Array.from(this.runningNetworks.keys()))
    }
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

  public getConfig(uuid: string) {
    return AppManager.data.configUUIDMap.get(uuid)
  }

  public getEditingConfig() {
    return AppManager.data.configUUIDMap.get(AppManager.uiState.editingInstance ?? "") ?? ContentUtil.getDefaultConfig("")
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
