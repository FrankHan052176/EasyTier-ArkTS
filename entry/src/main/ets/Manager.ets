import { distributedDeviceManager } from "@kit.DistributedServiceKit";
import { abilityAccessCtrl } from "@kit.AbilityKit";
import Logger from "./util/Logger";
import EventHelper from "./util/EventHelper";
import { cidr, Config, exit_node, listener, network_identity, peer, route, SharedPeer } from "./util/config/ETConfig";
import { SafeSet } from "./util/SafeSet";
import { distributedKVStore, preferences } from "@kit.ArkData";
import { objectToHomoTOML, tomlToConfig } from "./util/Conversion";
import { NetworkInstanceRunningInfoWithUnwrappedEvents } from "./util/info/PeerInfo";
import { rcp } from "@kit.RemoteCommunicationKit";
import { JSON } from "@kit.ArkTS";

@ObservedV2
class Manager {
  deviceManager: distributedDeviceManager.DeviceManager = distributedDeviceManager.createDeviceManager("top.frankhan.easytier")
  @Trace distributePerm: abilityAccessCtrl.GrantStatus = abilityAccessCtrl.GrantStatus.PERMISSION_DENIED
  @Trace locPerm: abilityAccessCtrl.GrantStatus = abilityAccessCtrl.GrantStatus.PERMISSION_DENIED
  @Trace qqgroups: string[] = []
  @Trace sharedPeers: Map<string,SharedPeer> = new Map
  @Trace configs = new Map<string, Config>()
  @Trace peers = new SafeSet<peer>(undefined, (value) => {
    this.KVStore?.put("peer_"+value.toString(), value.toString())
  }, (value) => {
    this.KVStore?.delete("peer_"+value.toString())
  })
  @Trace network_identities = new SafeSet<network_identity>(undefined, (value) => {
    this.KVStore?.put("network_identity_"+value.toString(), value.toString())
  }, (value) => {
    this.KVStore?.delete("network_identity_"+value.toString())
  })
  @Trace listeners = new SafeSet<listener>(undefined, (value) => {
    this.KVStore?.put("listener_"+value.toString(), value.toString())
  }, (value) => {
    this.KVStore?.delete("listener_"+value.toString())
  })
  @Trace routes = new SafeSet<route>(undefined, (value) => {
    this.KVStore?.put("route_"+value.toString(), value.toString())
  }, (value) => {
    this.KVStore?.delete("route_"+value.toString())
  })
  @Trace cidrs = new SafeSet<cidr>(undefined, (value) => {
    this.KVStore?.put("cidr_"+value.toRawString(), value.toRawString())
  }, (value) => {
    this.KVStore?.delete("cidr_"+value.toRawString())
  })
  @Trace exit_nodes = new SafeSet<exit_node>(undefined, (value) => {
    this.KVStore?.put("exit_node_"+value.toString(), value.toString())
  }, (value) => {
    this.KVStore?.delete("exit_node_"+value.toString())
  })
  @Trace width: number = 0
  @Trace height: number = 0
  KVManager: distributedKVStore.KVManager | undefined
  KVStore: distributedKVStore.DeviceKVStore | undefined
  Preferences: preferences.Preferences | undefined
  @Trace infos = new Map<string,NetworkInstanceRunningInfoWithUnwrappedEvents> ()
  @Trace runningInstances: Array<string> = new Array
  @Trace errorMsgs: Array<string> = new Array
  needTunInstances: Set<string> = new Set
  show_log: boolean = false
  @Trace preference_log: boolean = false

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
    const request = new rcp.Request("https://uptime.easytier.cn/api/nodes?per_page=50&page="+page, 'GET');
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
        this.sharedPeers.set(peer.peer.toString(), peer)
      })
      if (total_pages > 1 && page == 1) {
        Logger.info("[Manager] sharedPeers total pages:"+total_pages)
        for (let index = 2; index <= total_pages; index++) {
          Logger.info("[Manager] read page "+index)
          this.updateSharedPeers(index)
        }
      }
    })
    return Promise.resolve()
  }

  async updateQQGroups(): Promise<void> {
    const request = new rcp.Request("https://easytier.cn/", 'GET');
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
    })
    return Promise.resolve()
  }

  async readDB(kvm:distributedKVStore.KVManager) {
    this.KVManager = kvm
    const options: distributedKVStore.Options = {
      createIfMissing: true,
      encrypt: false,
      backup: false,
      autoSync: false,
      kvStoreType: distributedKVStore.KVStoreType.DEVICE_COLLABORATION,
      securityLevel: distributedKVStore.SecurityLevel.S2
    };
    try {
      kvm.getKVStore<distributedKVStore.DeviceKVStore>('configs', options, (err, store: distributedKVStore.DeviceKVStore) => {
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
            this.peers.add(new peer().setUri(entry.value.value.toString()), false)
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
      })
    } catch (e) {
      Logger.error(`[Manager] An unexpected error occurred. Code:${e.code},message:${e.message}`);
    }
  }

  addConfig(config: Config) {
    this.configs.set(config.instance_id, config)
    this.peers.addSet(config.peer)
    this.network_identities.add(config.network_identity)
    this.listeners.addSet(config.listeners)
    this.routes.addSet(config.routes)
    this.exit_nodes.addSet(config.exit_nodes)
    let str = objectToHomoTOML(config)
    this.KVStore?.put("config_"+config.instance_id, str, (err) => {
      if (err) {
        Logger.error("[Manager] kvstore delete "+err.code)
      }else {
        this.KVStore?.commit()
      }
    })
  }

  deleteConfig(config: Config) {
    this.configs.delete(config.instance_id)
    this.KVStore?.delete("config_"+config.instance_id, (err) => {
      if (err) {
        Logger.error("[Manager] kvstore delete "+err.code)
      }else {
        this.KVStore?.commit()
      }
    })
  }

  updateConfig(config: Config) {
    Logger.debug("updateConfig "+config.instance_id)
    this.KVStore?.put("config_"+config.instance_id, objectToHomoTOML(config), (err) => {
      if (err) {
        Logger.error("[Manager] kvstore delete "+err.code)
      }else {
        this.KVStore?.commit()
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

  isStarted(config: Config): boolean {
    if (this.infos.size <= 0) {
      return false
    }else {
      return this.infos.has(config.instance_id)
    }
  }

  isRunning(config: Config): boolean {
    if (this.runningInstances.length <= 0) {
      return false
    }else {
      return this.runningInstances[0] == config.instance_id
    }
  }

  getPeers(): SafeSet<peer> {
    return this.peers
  }

  getConfigs(): Config[] {
    return Array.from(this.configs.values())
  }
}

export default new Manager()