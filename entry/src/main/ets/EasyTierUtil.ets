import entry from 'libentry.so'
import { NetworkInstanceRunningInfo } from './protobuf/api_manage'
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

@Concurrent
async function readInfoWorker(): Promise<void> {
  setInterval(() => {
    let infos = easytier.collectNetworkInfos()
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
  @Trace runningNetworks: Map<string, NetworkInstanceRunningInfo> = new Map
  @Trace instanceInfos: Map<string, InstanceInfo> = new Map
  @Trace needTUN: string | undefined
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

    this.task1 = new taskpool.LongTask(readInfoWorker)
    this.task2 = new taskpool.LongTask(readLogsWorker)
    taskpool.execute(this.task1)
    taskpool.execute(this.task2)
  }

  destroy() {
    taskpool.terminateTask(this.task1)
    taskpool.terminateTask(this.task2)
  }

  version() {
    return easytier.easytierVersion()
  }

  convertToml2NetworkConfig(toml: string): string {
    return easytier.convertTomlToNetworkConfig(toml)
  }

  processNetworkInfos(infos: KeyValuePair[]) {
    let networks = new Set<string>()
    for (const info of infos) {
      networks.add(info.key)
      let newInfo = JSON.parse(info.value) as NetworkInstanceRunningInfo
      if (!newInfo.running) {
        Logger.error("ReadErrorInfo: " + newInfo.error_msg, this)
        this.stop()
        continue
      }
      this.runningNetworks.set(info.key, newInfo)
      if (!this.instanceInfos.has(info.key)) {
        this.instanceInfos.set(info.key, new InstanceInfo())
      } else {
        this.instanceInfos.get(info.key)?.update(newInfo)
      }
      EventHelper.emitterPublish("updateInfo_" + info.key)
      if (this.needTUN === info.key && newInfo.my_node_info?.virtual_ipv4 &&
        newInfo.my_node_info?.virtual_ipv4?.address) {
        this.needTUN = undefined
        let config = AppManager.data.configUUIDMap.get(info.key)!
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
      }
      if (this.needTUN !== info.key && (AppManager.preference.vpn_routes || deviceInfo.sdkApiVersion >= 20)) {
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
        if (easytier.parseNetworkConfig(JSON.stringify(config))) {
          if (!config.no_tun) {
            this.needTUN = uuid
          }
          AppManager.permission.requestLocPerm().then(() => {
            EventHelper.emitterPublish("start_bg", {
              data: {
                cfg: JSON.stringify(config),
                uuid: byCard?undefined:uuid
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

  public stop() {
    EventHelper.emitterPublish("stop_bg")
    easytier.stopNetworkInstance(Array.from(this.runningNetworks.keys()))
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
        Logger.error("NetworkSegment constructor throw a error:[" + route + "] is invalid.", this)
        return false
      }
    }
    return result
  }
}
