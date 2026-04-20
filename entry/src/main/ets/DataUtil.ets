import { Logger, LogLocate } from './util/Logger';
import { util } from '@kit.ArkTS';
import { FieldValueDataSource } from './class/FieldValueDataSource';
import { Url } from './class/config/Url';
import { NetworkConfig, NetworkingMethod } from './protobuf/api_manage';
import { ContentUtil } from './ContentUtil';
import { AppManager } from './AppManager';
import { getHostname } from './util/Conversion';
import { distributedKVStore, preferences, ValueType } from '@kit.ArkData';
import { deviceInfo } from '@kit.BasicServicesKit';
import { FieldValue } from './class/config/Basic';
import { Cidr } from './class/config/Cidr';
import { PortForward } from './class/config/PortForward';
import { NetworkName } from './class/config/NetworkName';
import { IP } from './class/config/IP';
import { HMRouterTransitions } from '@hadss/hmrouter-transitions';
import { HMRouterMgr } from '@hadss/hmrouter';

@LogLocate("DataUtil")
@ObservedV2
export class DataUtil {
  @Trace globalDataMap: Map<string, FieldValueDataSource> = new Map
  @Trace configUUIDMap: Map<string, NetworkConfig> = new Map
  @Trace tempConfigMap: Map<string, NetworkConfig> = new Map

  public isFavorite(uuid: string | undefined) {
    if (uuid) {
      return uuid === AppManager.uiState.favorite
    } else {
      return false
    }
  }

  public changeFavorite(uuid: string | undefined) {
    if (!uuid) {
      return
    }
    if (this.isFavorite(uuid)) {
      AppManager.uiState.favorite = undefined
    } else {
      AppManager.uiState.favorite = uuid
    }
  }

  public initDataSource(type: string, arr: string[]) {
    let values: FieldValue[] = []
    for (const raw of arr) {
      if (type === "cidr" || type === "route") {
        let value = new Cidr()
        if (value.fromString(raw)) {
          values.push(value)
        }
      } else if (type === "peer" || type === "listener" || type === "mapped_listener") {
        let value = new Url()
        if (value.fromString(raw)) {
          values.push(value)
        }
      } else if (type === "ip") {
        let value = new IP()
        if (value.fromString(raw)) {
          values.push(value)
        }
      } else if (type === "network_name") {
        let value = new NetworkName()
        if (value.fromString(raw)) {
          values.push(value)
        }
      } else if (type === "port_forward") {
        let value = new PortForward()
        if (value.fromString(raw)) {
          values.push(value)
        }
      }
    }
    let dataSource = new FieldValueDataSource(type, values)
    this.globalDataMap.set(type, dataSource)
  }

  public getDataSource(type: string): FieldValueDataSource {
    if (this.globalDataMap.has(type)) {
      return this.globalDataMap.get(type)!
    } else {
      let dataSource = new FieldValueDataSource(type)
      this.globalDataMap.set(type, dataSource)
      return dataSource
    }
  }

  public async init() {
    if (AppManager.KVManager) {
      Logger.warn('Find old Data.', this)
      const options: distributedKVStore.Options = {
        createIfMissing: true,
        encrypt: false,
        backup: false,
        autoSync: false,
        kvStoreType: distributedKVStore.KVStoreType.DEVICE_COLLABORATION,
        securityLevel: distributedKVStore.SecurityLevel.S2
      };
      try {
        let store = await AppManager.KVManager.getKVStore<distributedKVStore.DeviceKVStore>('configs', options)
        Logger.debug('Succeeded in getting KVStore.', this)
        store.getEntries("peer_", (err, entries) => {
          if (err) {
            Logger.error(`Failed to get KVStore: Code:${err.code},message:${err.message}`, this);
            return;
          }
          if (entries.length == 0) {
            Logger.debug('No Peer', this)
          } else {
            entries.forEach((entry) => {
              let value = new Url()
              if (value.fromString(entry.value.value.toString())) {
                Logger.debug('Read Peer: ' + value.toString(), this)
                this.getDataSource("peer").add(value)
              }
            })
          }
          store.getEntries("config_", (err, entries) => {
            if (err) {
              Logger.error(`Failed to get KVStore: Code:${err.code},message:${err.message}`, this);
              return;
            }
            if (entries.length == 0) {
              Logger.debug('No Config', this)
            } else {
              entries.forEach((entry) => {
                let toml = entry.value.value.toString()
                Logger.debug('Read Config: ' + entry.key, this)
                this.importToml(toml)
              })
            }
            AppManager.KVManager!.deleteKVStore("top.frankhan.easytier", 'configs').catch(() => {
            })
          })
        })
      } catch (err) {
        Logger.error(`Failed to get KVStore: Code:${err.code},message:${err.message}`, this);
        AppManager.KVManager!.deleteKVStore("top.frankhan.easytier", 'configs').catch(() => {
        })
      }
    }
  }

  public safeUUID(): string {
    let uuid = util.generateRandomUUID()
    while (this.configUUIDMap.has(uuid)) {
      uuid = util.generateRandomUUID()
    }
    return uuid
  }

  public newConfig(name: string): NetworkConfig {
    let config = ContentUtil.getDefaultConfig(getHostname())
    config.instance_id = this.safeUUID()
    this.configUUIDMap.set(config.instance_id, config)
    AppManager.uiState.configUUIDNameMap.set(config.instance_id, name)
    AppManager.preference.addConfig(config.instance_id, name, config)
    const animator = HMRouterTransitions.cardLongTake("instance_card_" + config.instance_id, "edit_content");
    AppManager.uiState.editingInstance = config.instance_id
    HMRouterMgr.push({ pageUrl: 'EditPage', param: {uuid:config.instance_id, unsafe: false}, animator: animator });
    return config
  }

  public readConfig(uuid: string, name: string, config: NetworkConfig) {
    this.configUUIDMap.set(uuid, config)
    AppManager.uiState.configUUIDNameMap.set(uuid, name)
    AppManager.preference.addConfig(config.instance_id!, name, config)
    return config
  }

  public importToml(cfg_toml: string): boolean {
    if (deviceInfo.productModel === "emulator") {
      return false
    }
    let cfg = AppManager.easytier.convertToml2NetworkConfig(cfg_toml)
    Logger.debug("convertConfig: " + cfg, this)
    if (cfg.startsWith("ERROR")) {
      return false
    }
    let instance_name = cfg_toml.match(/^\s*instance_name\s*=\s*["'](.+?)["']\s*(?:#.*)?$/m)
    Logger.debug("import toml find name: " + JSON.stringify(instance_name))
    let name = instance_name ? instance_name[1] : undefined
    let config: NetworkConfig
    try {
      config = JSON.parse(cfg)
    } catch (e) {
      Logger.error(`importToml parse error: ${JSON.stringify(e)}`, this)
      return false
    }
    if (config.networking_method === NetworkingMethod.PublicServer && config.public_server_url) {
      config.hostname = getHostname()
      config.networking_method = NetworkingMethod.Manual
      config.peer_urls.push(config.public_server_url)
    }
    config.proxy_cidrs.forEach(cidrStr => {
      let cidr = new Cidr()
      if (cidr.fromString(cidrStr)) {
        this.getDataSource("cidr").add(cidr)
      }
    })
    config.routes.forEach(routeStr => {
      let route = new Cidr()
      if (route.fromString(routeStr)) {
        this.getDataSource("route").add(route)
      }
    })
    config.peer_urls.forEach(urlStr => {
      let url = new Url()
      if (url.fromString(urlStr)) {
        this.getDataSource("peer").add(url)
      }
    })
    config.listener_urls.forEach(urlStr => {
      let url = new Url()
      if (url.fromString(urlStr)) {
        this.getDataSource("listener").add(url)
      }
    })
    config.mapped_listeners.forEach(urlStr => {
      let url = new Url()
      if (url.fromString(urlStr)) {
        this.getDataSource("mapped_listener").add(url)
      }
    })
    config.exit_nodes.forEach(nodeStr => {
      let ip = new IP()
      if (ip.fromString(nodeStr)) {
        this.getDataSource("ip").add(ip)
      }
    })
    config.relay_network_whitelist.forEach(wlStr => {
      let name = new NetworkName()
      if (name.fromString(wlStr)) {
        this.getDataSource("network_name").add(name)
      }
    })
    config.port_forwards.forEach(pfConfig => {
      let pf = new PortForward()
      if (pf.readFrom(pfConfig)) {
        this.getDataSource("port_forward").add(pf)
      }
    })
    this.configUUIDMap.set(config.instance_id!, config)
    AppManager.uiState.configUUIDNameMap.set(config.instance_id!, name ?? config.instance_id!)

    AppManager.preference.addConfig(config.instance_id!, name ?? config.instance_id!, config)
    const animator = HMRouterTransitions.cardLongTake("instance_card_" + config.instance_id, "edit_content");
    AppManager.uiState.editingInstance = config.instance_id
    HMRouterMgr.push({ pageUrl: 'EditPage', param: {uuid:config.instance_id, unsafe: false}, animator: animator });
    return true
  }

  public delConfig(uuid: string): boolean {
    if (AppManager.uiState.favorite === uuid) {
      AppManager.uiState.favorite = undefined
    }
    if (AppManager.uiState.selected === uuid) {
      AppManager.uiState.selected = undefined
    }
    if (this.configUUIDMap.has(uuid)) {
      try {
        AppManager.preference.configIDPreferences?.deleteSync(uuid)
        AppManager.preference.configPreferences.delete(uuid)
        AppManager.preference.configIDPreferences?.flushSync()
      } catch (error) {}
      preferences.deletePreferences(AppManager.content.context!, uuid)
      let result = this.configUUIDMap.delete(uuid)
      AppManager.uiState.configUUIDNameMap.delete(uuid)
      return result
    } else {
      return false
    }
  }
}
