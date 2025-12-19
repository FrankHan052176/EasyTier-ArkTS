import entry from 'libentry.so'
import { NetworkInstanceRunningInfo } from './protobuf/api_manage'
import easytier from 'easytier-ohrs'
import { EventHelper } from './util/EventHelper'
import { AppManager } from './AppManager'
import { Logger, LogLocate } from './util/Logger'
import { sendToast } from './ToastUtil'
import { InstanceInfo } from './class/InstanceInfo'
import { convertAddrToIp } from './util/Conversion'
import { NetworkSegment } from './class/NetworkSegment'
import { SafeSet } from './util/SafeSet'
import { deviceInfo } from '@kit.BasicServicesKit'
import { ValueType } from '@kit.ArkData'

@LogLocate("EasyTierUtil")
@ObservedV2
export class EasyTierUtil {
  @Trace appLogs: Set<string> = new Set
  @Trace nmLogs: Set<string> = new Set
  @Trace ohLogs: Set<string> = new Set
  @Trace runningNetworks: Map<string, NetworkInstanceRunningInfo> = new Map
  @Trace instanceInfos: Map<string, InstanceInfo> = new Map
  @Trace selected: string | undefined
  @Trace needTUN: string | undefined
  tunRoutes: SafeSet<NetworkSegment> = new SafeSet()

  @Monitor("selected")
  onChange(monitor: IMonitor) {
    monitor.dirty.forEach((path: string) => {
      if (AppManager.preference.preferences !== undefined && !AppManager.preference.isInit) {
        try {
          if (monitor.value(path)?.now) {
            AppManager.preference.preferences.putSync(path, monitor.value(path)?.now as ValueType)
          } else {
            AppManager.preference.preferences.putSync(path, "" as ValueType)
          }
          AppManager.preference.preferences.flushSync()
        } catch (error) {
          Logger.error(`PreferenceUtil failed to change ${path}.\n${error}`, this)
        }
      }
    })
  }

  init() {
    setInterval(() => {
      this.readLogs()
    }, 500)
    setInterval(() => {
      this.readInfo()
    }, 100)
  }

  version() {
    return easytier.easytierVersion()
  }

  convertToml2NetworkConfig(toml: string): string {
    return easytier.convertTomlToNetworkConfig(toml)
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

  private readInfo() {
    let infos = easytier.collectNetworkInfos()
    let networks = new Set<string>()
    for (const info of infos) {
      networks.add(info.key)
      let newInfo: NetworkInstanceRunningInfo = JSON.parse(info.value)
      if (!newInfo.running) {
        Logger.error("ReadErrorInfo: " + newInfo.error_msg, this)
        this.stop()
        continue
      }
      let isNew: boolean = false
      if (!this.runningNetworks.has(info.key)) {
        isNew = true
      }
      this.runningNetworks.set(info.key, newInfo)
      if (!this.instanceInfos.has(info.key)) {
        this.instanceInfos.set(info.key, new InstanceInfo())
      }else {
        this.instanceInfos.get(info.key)?.update(newInfo)
      }
      if (isNew) {
        EventHelper.emitterPublish("running_instance_added", {
          data: {
            id: info.key
          }
        })
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
    EventHelper.commonPublishData("status_bar_infos", Array.from(networks.keys()).join(" "))
    for (const uuid of Array.from(this.runningNetworks.keys())) {
      if (!networks.has(uuid)) {
        this.runningNetworks.delete(uuid)
        this.instanceInfos.delete(uuid)
      }
    }
  }

  private readLogs() {
    let appLogs = entry.getAppLog()
    if (this.appLogs.size < appLogs.length) {
      appLogs.forEach((value) => {
        this.appLogs.add(value)
      })
    }
    let nmLogs = entry.getNetworkManagerLog()
    if (this.nmLogs.size < nmLogs.length) {
      nmLogs.forEach((value) => {
        this.nmLogs.add(value)
      })
    }
    let ohLogs = entry.getOHLog()
    if (this.ohLogs.size < ohLogs.length) {
      ohLogs.forEach((value) => {
        this.ohLogs.add(value)
      })
    }
  }

  public start(uuid: string | undefined = this.selected): boolean {
    if (uuid) {
      let config = AppManager.data.configUUIDMap.get(uuid)
      if (config) {
        Logger.debug("start:" + JSON.stringify(config), this)
        if (easytier.parseNetworkConfig(JSON.stringify(config))) {
          if (!config.no_tun) {
            this.needTUN = uuid
          }
          EventHelper.emitterPublish("start_bg", {
            data: {
              cfg: JSON.stringify(config),
              id: uuid
            }
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
    return AppManager.data.configUUIDMap.get(AppManager.data.editingInstance ?? "")
  }

  public getEditingInstance() {
    return AppManager.data.editingInstance
  }

  public isEditingRunning(): boolean {
    return this.isRunning(this.getEditingInstance())
  }

  public isFavoritesRunning(): boolean {
    return this.isRunning(AppManager.data.favorite)
  }
}