import { distributedDeviceManager } from "@kit.DistributedServiceKit";
import { abilityAccessCtrl } from "@kit.AbilityKit";
import Logger from "./util/Logger";
import EventHelper from "./util/EventHelper";
import { cidr, Config, exit_node, listener, network_identity, peer, route, SharedPeer,
  WrappedString } from "./util/config/ETConfig";
import { distributedKVStore, preferences } from "@kit.ArkData";
import { handleNewInfo, objectToHomoTOML, tomlToConfig } from "./util/Conversion";
import { NetworkInstanceRunningInfo, NetworkInstanceRunningInfoWithUnwrappedEvents } from "./util/info/PeerInfo";
import { rcp } from "@kit.RemoteCommunicationKit";
import { JSON } from "@kit.ArkTS";
import { requestLocPerm, updatePermStatus } from "./util/Permission";
import { deferredLink } from "@kit.AppLinkingKit";
import { readConfig } from "./util/Compress";
import easytier from "libeasytier_ohrs.so"
import entry from 'libentry.so'
import { SafeSet } from "./util/SafeSet";
import { SafeLightWeightSet } from "./util/SafeLightWeightSet";
import { CompSize } from "./pages/nodes/AutoSortContainer";

export enum UIType {
  Column_1, Column_2, Column_3
}

@ObservedV2
class Manager {
  deviceManager: distributedDeviceManager.DeviceManager = distributedDeviceManager.createDeviceManager("top.frankhan.easytier")
  @Trace distributePerm: abilityAccessCtrl.GrantStatus = abilityAccessCtrl.GrantStatus.PERMISSION_DENIED
  @Trace locPerm: abilityAccessCtrl.GrantStatus = abilityAccessCtrl.GrantStatus.PERMISSION_DENIED
  @Trace qqgroups: string[] = []
  @Trace sharedPeers = new SafeLightWeightSet<SharedPeer>().doDisableUpdate()
  @Trace configs = new Map<string, Config>()
  @Trace lastUsedConfig: Config[] = []
  @Trace peers = new SafeLightWeightSet<peer>(undefined, () => {return new peer()})
  @Trace network_identities = new SafeLightWeightSet<network_identity>(undefined, () => {return new network_identity()})
  @Trace listeners = new SafeLightWeightSet<listener>(undefined, () => {return new listener()})
  @Trace routes = new SafeLightWeightSet<route>(undefined, () => {return new route()})
  @Trace cidrs = new SafeLightWeightSet<cidr>(undefined, () => {return new cidr()})
  @Trace exit_nodes = new SafeLightWeightSet<exit_node>(undefined, () => {return new exit_node()})
  @Trace whitelist = new SafeLightWeightSet<WrappedString>(undefined, () => {return new WrappedString()})
  @Trace width: number = 0
  @Trace height: number = 0
  @Trace statusBarHeight: number = 0
  @Trace navigationBarHeight: number = 0
  @Trace navigationHeight: number = 0
  @Trace compHeight: number = 0
  @Trace uiType: UIType = UIType.Column_1
  KVManager: distributedKVStore.KVManager | undefined
  KVStore: distributedKVStore.DeviceKVStore | undefined
  Preferences: preferences.Preferences | undefined
  @Trace info_uuid: string | undefined = undefined
  @Trace info: NetworkInstanceRunningInfoWithUnwrappedEvents | undefined = undefined
  @Trace runningInstances: Array<string> = new Array
  @Trace appLogs: Set<string> = new Set
  @Trace nmLogs: Set<string> = new Set
  @Trace ohLogs: Set<string> = new Set
  needTunInstances: Set<string> = new Set
  show_log: boolean = false
  @Trace preference_log: boolean = false
  uiContext: UIContext | undefined = undefined
  @Trace auto_start: string | undefined = undefined
  @Trace comp_sequence: string[] = ["Instances", "Logs"]
  @Trace comp_size: Map<string, CompSize> = new Map([["Instances", new CompSize()], ["Logs", new CompSize()]])

  onInit() {
    updatePermStatus()
    this.updateQQGroups()
    this.updateSharedPeers()
    this.readDB()
    setInterval(() => {
      this.updateQQGroups()
      this.updateSharedPeers()
    }, 1800000)
    setInterval(() => {
      let infos = easytier.collectNetworkInfos()
      if (infos.length > 0) {
        let info = JSON.parse(infos[0].value) as NetworkInstanceRunningInfo
        handleNewInfo(info, infos[0].key)
        this.info_uuid = infos[0].key
      }else if (this.info != undefined) {
        this.info = undefined
        this.info_uuid = undefined
      }
      let appLogs = entry.getAppLog()
      if (this.appLogs.size < appLogs.length) {
        appLogs.slice(this.appLogs.size, appLogs.length).forEach((value) => {
          this.appLogs.add(value)
        })
      }
      let nmLogs = entry.getNetworkManagerLog()
      if (this.nmLogs.size < nmLogs.length) {
        nmLogs.slice(this.nmLogs.size, nmLogs.length).forEach((value) => {
          this.nmLogs.add(value)
        })
      }
      let ohLogs = entry.getOHLog()
      if (this.ohLogs.size < ohLogs.length) {
        ohLogs.slice(this.ohLogs.size, ohLogs.length).forEach((value) => {
          this.ohLogs.add(value)
        })
      }
      this.runningInstances = easytier.collectRunningNetwork()
    }, 100)
    try {
      this.preference_log = this.Preferences!.getSync("show_log", false).valueOf() as boolean
    } catch (e) {
      Logger.error(`[Index] An unexpected error occurred. Code:${e.code},message:${e.message}`);
    }
    try {
      this.Preferences!.on("dataChange", ["show_log"], (value) => {
        for (const keyValue of Object.entries(value)) {
          this.preference_log = (keyValue[1]).valueOf() as boolean
        }
      })
    } catch (e) {
      Logger.error(`[Index] An unexpected error occurred. Code:${e.code},message:${e.message}`);
    }
    EventHelper.emitterListener("windowSizeChange", (data) => {
      this.width = this.uiContext!.px2vp(data.data!.width as number)
      this.height = this.uiContext!.px2vp(data.data!.height as number)
      if (this.width < 720) {
        animateToImmediately({
          duration: 300,
          curve: Curve.Friction
        }, () => {
          this.uiType = UIType.Column_1
        })
      }else if (this.width >= 1080) {
        animateToImmediately({
          duration: 300,
          curve: Curve.Friction
        }, () => {
          this.uiType = UIType.Column_3
        })
      }else {
        animateToImmediately({
          duration: 300,
          curve: Curve.Friction
        }, () => {
          this.uiType = UIType.Column_2
        })
      }
    })
    if (canIUse("SystemCapability.BundleManager.AppLinking.DeferredLink")) {
      deferredLink.popDeferredLink().then((link: string) => {
        if (link) {
          readConfig(link).then(() => {
            try {
              this.uiContext!.getPromptAction().showToast({
                message: "成功导入分享的配置"
              })
            } catch (e) {
              Logger.error(`[Index] An unexpected error occurred. Code:${e.code},message:${e.message}`);
            }
          }, (reason:string) => {
            try {
              this.uiContext!.getPromptAction().showToast({
                message: "导入配置失败\n" + reason
              })
            } catch (e) {
              Logger.error(`[Index] An unexpected error occurred. Code:${e.code},message:${e.message}`);
            }
          })
        }
      })
    }
  }

  updateDistributePerm(status: number) {
    if (status === 2) {
      Logger.error("[Manager] invalid request of DistributePerm")
    }else {
      Logger.info("[Manager] update DistributePerm: "+status)
      this.distributePerm = status
      EventHelper.emitterPublish("update_distribute")
    }
  }

  updateLocPerm(status: number) {
    if (status === 2) {
      Logger.error("[Manager] invalid request of LocPerm")
    }else {
      Logger.info("[Manager] update LocPerm: "+status)
      this.locPerm = status
      EventHelper.emitterPublish("update_loc")
    }
  }

  async updateSharedPeers(page: number = 1): Promise<void> {
    const request = new rcp.Request("https://uptime.easytier.cn/api/nodes?per_page=50&tags=%E5%9B%BD%E5%86%85&page="+page, 'GET');
    try {
      const session = rcp.createSession();
      session.fetch(request).then((rep: rcp.Response) => {
        let obj = rep.toJSON()
        if (!obj) return;
        let success: boolean = obj["success"]
        if (!success) return;
        let data: object = obj["data"]
        let total: number = data["total"]
        let total_pages: number = data["total_pages"]
        let items: Array<object> = data["items"]
        Logger.info("[Manager] sharedPeers total peers:"+total)
        items.forEach((item: object) => {
          let peer = new SharedPeer(item)
          this.sharedPeers.add(peer)
        })
        if (total_pages > 1 && page == 1) {
          Logger.info("[Manager] sharedPeers total pages:"+total_pages)
          for (let index = 2; index <= total_pages; index++) {
            Logger.info("[Manager] read page "+index)
            this.updateSharedPeers(index)
          }
        }
      }).catch(() => {
        Logger.error(`[Manager] updateSharedPeers()::An unexpected error occurred.`);
      })
    } catch (e) {
      Logger.error(`[Manager] An unexpected error occurred. Code:${e.code},message:${e.message}`);
    }
    return Promise.resolve()
  }

  async updateQQGroups(): Promise<void> {
    const request = new rcp.Request("https://easytier.cn/", 'GET');
    try {
      const session = rcp.createSession();
      session.fetch(request).then((rep: rcp.Response) => {
        const pattern: RegExp = /<a\s+href="[^"]*"\s+target="_blank"\s+rel="noreferrer">([^<]*)<\/a>/gi;
        const texts: string[] = [];

        let match: RegExpExecArray | null;
        while ((match = pattern.exec(rep.toString()!)) !== null) {
          if (match[1]) {
            let text = match[1].trim()
            if (!Number.isNaN(parseInt(text))) {
              texts.push(text);
            }else {
              // TODO discord && tg 跳转
            }
          }
        }
        this.qqgroups = texts;
        Logger.info("[Manager] Update QQ Groups:"+JSON.stringify(this.qqgroups))
      }).catch(() => {
        Logger.error(`[Manager] updateQQGroups()::An unexpected error occurred.`);
      })
    } catch (e) {
      Logger.error(`[Manager] An unexpected error occurred. Code:${e.code},message:${e.message}`);
    }
    return Promise.resolve()
  }

  updateAutoStart(uuid: string) {
    if (this.configs.has(uuid)) {
      if (this.auto_start == uuid) {
        this.auto_start = undefined
      }else {
        this.auto_start = uuid
      }
    }
  }

  async readDB() {
    const options: distributedKVStore.Options = {
      createIfMissing: true,
      encrypt: false,
      backup: false,
      autoSync: false,
      kvStoreType: distributedKVStore.KVStoreType.DEVICE_COLLABORATION,
      securityLevel: distributedKVStore.SecurityLevel.S2
    };
    try {
      this.KVManager!.getKVStore<distributedKVStore.DeviceKVStore>('configs', options, (err, store: distributedKVStore.DeviceKVStore) => {
        if (err) {
          Logger.error(`[Manager] Failed to get KVStore: Code:${err.code},message:${err.message}`);
          return;
        }
        Logger.debug('[Manager] Succeeded in getting KVStore.');
        this.KVStore = store;
        store.getEntries("config_", (err, entries) => {
          if (err) {
            Logger.error(`[Manager] Failed to getEntries KVStore: Code:${err.code},message:${err.message}`);
            return;
          }
          entries.forEach((entry) => {
            Logger.info("[Manager] find entry "+entry.key)
            let config = tomlToConfig(entry.value.value.toString())
            if (config) {
              this.configs.set(config.instance_id, config)
              this.peers.addSet(config.peer, false)
              this.network_identities.add(config.network_identity, false)
              this.listeners.addSet(config.listeners, false)
              this.routes.addSet(config.routes, false)
              this.exit_nodes.addSet(config.exit_nodes, false)
              this.whitelist.addSet(config.flags.relay_network_whitelist.whitelist, false)
            }
          })
        })
        store.getEntries("peer_", (err, entries) => {
          if (err) {
            Logger.error(`[Manager] Failed to getEntries KVStore: Code:${err.code},message:${err.message}`);
            return;
          }
          entries.forEach((entry) => {
            Logger.info("[Manager] find peer "+entry.key)
            let value = entry.value.value.toString()
            let shared = this.sharedPeers.map.get(value)
            if (shared) {
              shared.changeEnabled(false)
            }else {
              this.peers.add(new peer().setUri(value), false)
            }
          })
        })
        store.getEntries("network_identity_", (err, entries) => {
          if (err) {
            Logger.error(`[Manager] Failed to getEntries KVStore: Code:${err.code},message:${err.message}`);
            return;
          }
          entries.forEach((entry) => {
            Logger.info("[Manager] find network_identity "+entry.key)
            this.network_identities.add(new network_identity().fromString(entry.value.value.toString()), false)
          })
        })
        store.getEntries("listener_", (err, entries) => {
          if (err) {
            Logger.error(`[Manager] Failed to getEntries KVStore: Code:${err.code},message:${err.message}`);
            return;
          }
          entries.forEach((entry) => {
            Logger.info("[Manager] find listener "+entry.key)
            this.listeners.add(new listener().fromString(entry.value.value.toString()), false)
          })
        })
        store.getEntries("route_", (err, entries) => {
          if (err) {
            Logger.error(`[Manager] Failed to getEntries KVStore: Code:${err.code},message:${err.message}`);
            return;
          }
          entries.forEach((entry) => {
            Logger.info("[Manager] find route "+entry.key)
            this.routes.add(new route().fromString(entry.value.value.toString()), false)
          })
        })
        store.getEntries("cidr_", (err, entries) => {
          if (err) {
            Logger.error(`[Manager] Failed to getEntries KVStore: Code:${err.code},message:${err.message}`);
            return;
          }
          entries.forEach((entry) => {
            Logger.info("[Manager] find cidr "+entry.key)
            this.cidrs.add(new cidr().fromString(entry.value.value.toString()), false)
          })
        })
        store.getEntries("exit_node_", (err, entries) => {
          if (err) {
            Logger.error(`[Manager] Failed to getEntries KVStore: Code:${err.code},message:${err.message}`);
            return;
          }
          entries.forEach((entry) => {
            Logger.info("[Manager] find exit_node "+entry.key)
            this.exit_nodes.add(new exit_node().fromString(entry.value.value.toString()), false)
          })
        })
        store.getEntries("wl_", (err, entries) => {
          if (err) {
            Logger.error(`[Manager] Failed to getEntries KVStore: Code:${err.code},message:${err.message}`);
            return;
          }
          entries.forEach((entry) => {
            Logger.info("[Manager] find whitelist "+entry.key)
            this.whitelist.add(new WrappedString(entry.value.value.toString()), false)
          })
        })
      })
    } catch (e) {
      Logger.error(`[Manager] An unexpected error occurred. Code:${e.code},message:${e.message}`);
    }
  }

  clearDB() {
    this.configs.forEach((value) => {
      this.KVStore?.delete("config_"+value.instance_id).catch(() => {
        Logger.error(`[Manager] clearDB()::delete()::An unexpected error occurred.`);
      })
    })
  }

  addConfig(config: Config) {
    this.configs.set(config.instance_id, config)
    this.peers.addSet(config.peer)
    this.network_identities.add(config.network_identity)
    this.listeners.addSet(config.listeners)
    this.routes.addSet(config.routes)
    this.exit_nodes.addSet(config.exit_nodes)
    this.whitelist.addSet(config.flags.relay_network_whitelist.whitelist)
    let str = objectToHomoTOML(config)
    this.KVStore?.put("config_"+config.instance_id, str, (err) => {
      if (err) {
        Logger.error("[Manager] kvstore delete "+err.code)
      }
    })
  }

  addConfigByName(name: string) {
    if (name.match(/^\s*$/) === null) {
      let config = new Config()
      config.instance_name = name
      animateToImmediately({
        duration: 300,
        curve: Curve.EaseIn
      }, () => {
        this.addConfig(config)
      })
    }
  }

  deleteConfig(config: Config) {
    this.configs.delete(config.instance_id)
    this.KVStore?.delete("config_"+config.instance_id, (err) => {
      if (err) {
        Logger.error("[Manager] kvstore delete "+err.code)
      }
    })
  }

  updateConfig(config: Config) {
    Logger.debug("updateConfig "+config.instance_id)
    this.KVStore?.put("config_"+config.instance_id, objectToHomoTOML(config), (err) => {
      if (err) {
        Logger.error("[Manager] kvstore delete "+err.code)
      }
    })
  }

  startInstance(config: Config): boolean {
    if (this.runningInstances.length > 0) {
      return false
    }else {
      EventHelper.emitterPublish("start_bg", {
        data: {
          inst_id: config.instance_id
        }
      })
      if (!config.flags.no_tun) {
        this.needTunInstances.add(config.instance_id)
      }
      return true
    }
  }

  stopInstance(config: Config): boolean {
    if (this.isStarted(config)) {
      EventHelper.emitterPublish("stop_bg", {
        data: {
          inst_id: config.instance_id
        }
      })
      this.needTunInstances.delete(config.instance_id)
      return true
    }else {
      return false
    }
  }

  changeInstanceStatus(config: Config) {
    if (this.info_uuid == config.instance_id) {
      if (!this.stopInstance(config)) {
        Logger.error("关闭网络失败")
      }
    }else {
      if (this.info != undefined) {
        this.uiContext?.getPromptAction().showToast({
          message: "请先关闭正在运行的网络"
        })
      }else if (this.uiContext != undefined && this.uiContext.getHostContext() != undefined) {
        requestLocPerm(this.uiContext.getHostContext()!).then((value) => {
          if (!value) {
            this.uiContext?.getPromptAction().showToast({
              message: "拒绝授权定位权限将无法进行后台保活"
            })
          }
          this.startInstance(config)
        })
      }
    }
  }

  isStarted(config: Config): boolean {
    if (this.info == undefined) {
      return false
    }else {
      return this.info_uuid == config.instance_id
    }
  }

  isRunning(config: Config): boolean {
    if (this.runningInstances.length <= 0) {
      return false
    }else {
      return this.runningInstances[0] == config.instance_id
    }
  }

  getConfigs(): Config[] {
    return Array.from(this.configs.values())
  }
}

export default new Manager()