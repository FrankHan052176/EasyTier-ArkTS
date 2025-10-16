import { distributedDeviceManager } from "@kit.DistributedServiceKit";
import { abilityAccessCtrl } from "@kit.AbilityKit";
import Logger from "./util/Logger";
import EventHelper from "./util/EventHelper";
import { cidr, Config, exit_node, listener, network_identity, peer, route, SharedPeer,
  WrappedString } from "./util/config/ETConfig";
import { distributedKVStore, preferences } from "@kit.ArkData";
import { objectToHomoTOML, tomlToConfig } from "./util/Conversion";
import { NetworkInstanceRunningInfoWithUnwrappedEvents } from "./util/info/PeerInfo";
import { rcp } from "@kit.RemoteCommunicationKit";
import { JSON } from "@kit.ArkTS";
import { SafeLightWeightSet } from "./util/SafeLightWeightSet";

export enum UIType {
  Column_1, Column_2, Column_3
}

@ObservedV2
class Manager {
  deviceManager: distributedDeviceManager.DeviceManager = distributedDeviceManager.createDeviceManager("top.frankhan.easytier")
  @Trace distributePerm: abilityAccessCtrl.GrantStatus = abilityAccessCtrl.GrantStatus.PERMISSION_DENIED
  @Trace locPerm: abilityAccessCtrl.GrantStatus = abilityAccessCtrl.GrantStatus.PERMISSION_DENIED
  @Trace qqgroups: string[] = []
  @Trace sharedPeers: Map<string,SharedPeer> = new Map
  @Trace configs = new Map<string, Config>()
  @Trace peers = new SafeLightWeightSet<peer>(undefined, () => {return new peer()}, (value) => {
    this.KVStore?.put("peer_"+value.toString(), value.toShortString()).catch(() => {
      Logger.error(`[Manager] peers::put::An unexpected error occurred.`);
    })
  }, (value) => {
    this.KVStore?.delete("peer_"+value.toString()).catch(() => {
      Logger.error(`[Manager] peers::delete::An unexpected error occurred.`);
    })
  })
  @Trace network_identities = new SafeLightWeightSet<network_identity>(undefined, () => {return new network_identity()}, (value) => {
    this.KVStore?.put("network_identity_"+value.toString(), value.toString()).catch(() => {
      Logger.error(`[Manager] network_identities::put::An unexpected error occurred.`);
    })
  }, (value) => {
    this.KVStore?.delete("network_identity_"+value.toString()).catch(() => {
      Logger.error(`[Manager] network_identities::delete::An unexpected error occurred.`);
    })
  })
  @Trace listeners = new SafeLightWeightSet<listener>(undefined, () => {return new listener()}, (value) => {
    this.KVStore?.put("listener_"+value.toString(), value.toString()).catch(() => {
      Logger.error(`[Manager] listeners::put::An unexpected error occurred.`);
    })
  }, (value) => {
    this.KVStore?.delete("listener_"+value.toString()).catch(() => {
      Logger.error(`[Manager] listeners::delete::An unexpected error occurred.`);
    })
  })
  @Trace routes = new SafeLightWeightSet<route>(undefined, () => {return new route()}, (value) => {
    this.KVStore?.put("route_"+value.toString(), value.toString()).catch(() => {
      Logger.error(`[Manager] routes::put::An unexpected error occurred.`);
    })
  }, (value) => {
    this.KVStore?.delete("route_"+value.toString()).catch(() => {
      Logger.error(`[Manager] routes::delete::An unexpected error occurred.`);
    })
  })
  @Trace cidrs = new SafeLightWeightSet<cidr>(undefined, () => {return new cidr()}, (value) => {
    this.KVStore?.put("cidr_"+value.toRawString(), value.toRawString()).catch(() => {
      Logger.error(`[Manager] cidrs::put::An unexpected error occurred.`);
    })
  }, (value) => {
    this.KVStore?.delete("cidr_"+value.toRawString()).catch(() => {
      Logger.error(`[Manager] cidrs::delete::An unexpected error occurred.`);
    })
  })
  @Trace exit_nodes = new SafeLightWeightSet<exit_node>(undefined, () => {return new exit_node()}, (value) => {
    this.KVStore?.put("exit_node_"+value.toString(), value.toString()).catch(() => {
      Logger.error(`[Manager] exit_nodes::put::An unexpected error occurred.`);
    })
  }, (value) => {
    this.KVStore?.delete("exit_node_"+value.toString()).catch(() => {
      Logger.error(`[Manager] exit_nodes::delete::An unexpected error occurred.`);
    })
  })
  @Trace whitelist = new SafeLightWeightSet<WrappedString>(undefined, () => {return new WrappedString()}, (value) => {
    this.KVStore?.put("wl_"+value.toString(), value.toString()).catch(() => {
      Logger.error(`[Manager] whitelist::put::An unexpected error occurred.`);
    })
  }, (value) => {
    this.KVStore?.delete("wl_"+value.toString()).catch(() => {
      Logger.error(`[Manager] whitelist::delete::An unexpected error occurred.`);
    })
  })
  @Trace width: number = 0
  @Trace height: number = 0
  @Trace uiType: UIType = UIType.Column_1
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
          this.sharedPeers.set(peer.peer.toString(), peer)
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

  getConfigs(): Config[] {
    return Array.from(this.configs.values())
  }
}

export default new Manager()