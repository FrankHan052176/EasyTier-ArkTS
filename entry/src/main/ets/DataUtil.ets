import { Logger, LogLocate } from './util/Logger';
import { util } from '@kit.ArkTS';
import { FieldValueDataSource } from './class/FieldValueDataSource';
import { Url } from './class/config/Url';
import { NetworkConfig, NetworkingMethod } from './protobuf/api_manage';
import { ContentUtil } from './ContentUtil';
import { AppManager } from './AppManager';
import { getHostname } from './util/Conversion';
import { distributedKVStore, preferences } from '@kit.ArkData';
import { deviceInfo } from '@kit.BasicServicesKit';
import { FieldValue } from './class/config/Basic';
import { Cidr } from './class/config/Cidr';
import { PortForward } from './class/config/PortForward';
import { NetworkName } from './class/config/NetworkName';
import { IP } from './class/config/IP';

@LogLocate("DataUtil")
@ObservedV2
export class DataUtil {
  @Trace globalDataMap: Map<string, FieldValueDataSource> = new Map
  @Trace configUUIDMap: Map<string, NetworkConfig> = new Map
  @Trace configNameUUIDMap: Map<string, string> = new Map
  @Trace configUUIDNameMap: Map<string, string> = new Map
  @Trace favoriteInstance: string | undefined
  @Trace editingInstance: string | undefined

  public isFavorite(uuid: string) {
    return uuid === this.favoriteInstance
  }

  public changeFavorite(uuid: string) {
    if (this.isFavorite(uuid)) {
      this.favoriteInstance = undefined
    } else {
      this.favoriteInstance = uuid
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
      } else if (type === "peer" || type === "listener" || type === "mappedListener") {
        let value = new Url()
        if (value.fromString(raw)) {
          values.push(value)
        }
      } else if (type === "ip") {
        let value = new IP()
        if (value.fromString(raw)) {
          values.push(value)
        }
      } else if (type === "string") {
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

  public init() {
    if (AppManager.KVManager && !AppManager.preference.noOldData) {
      const options: distributedKVStore.Options = {
        createIfMissing: true,
        encrypt: false,
        backup: false,
        autoSync: false,
        kvStoreType: distributedKVStore.KVStoreType.DEVICE_COLLABORATION,
        securityLevel: distributedKVStore.SecurityLevel.S2
      };
      try {
        AppManager.KVManager.getKVStore<distributedKVStore.DeviceKVStore>('configs', options,
          (err, store: distributedKVStore.DeviceKVStore) => {
            if (err) {
              Logger.error(`Failed to get KVStore: Code:${err.code},message:${err.message}`, this);
              return;
            }
            Logger.debug('Succeeded in getting KVStore.', this);
            store.getEntries("config_", (err, entries) => {
              if (err) {
                return;
              }
              if (entries.length == 0) {
                return;
              }
              entries.forEach((entry) => {
                let toml = entry.value.value.toString()
                this.importToml(toml)
              })
            })
            store.getEntries("peer_", (err, entries) => {
              if (err) {
                return;
              }
              if (entries.length == 0) {
                return;
              }
              entries.forEach((entry) => {
                let value = new Url()
                if (value.fromString(entry.value.value.toString())) {
                  this.getDataSource("peer").add(value)
                }
              })
            })
          })
        AppManager.preference.noOldData = true
      } catch (_) {
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
    this.configNameUUIDMap.set(name, config.instance_id)
    this.configUUIDNameMap.set(config.instance_id, name)
    AppManager.preference.addConfig(config.instance_id, name, config)
    return config
  }

  public readConfig(uuid: string, name: string, config: NetworkConfig) {
    this.configUUIDMap.set(uuid, config)
    this.configNameUUIDMap.set(name, uuid)
    this.configUUIDNameMap.set(uuid, name)
    return config
  }

  public importToml(cfg_toml: string): boolean {
    if (deviceInfo.productModel === "emulator") {
      return false
    }
    let cfg = AppManager.easytier.convertToml2NetworkConfig(cfg_toml)
    Logger.debug("convertConfig: " + cfg)
    if (cfg.startsWith("ERROR")) {
      return false
    }
    let config: NetworkConfig = JSON.parse(cfg)
    if (config.networking_method === NetworkingMethod.PublicServer && config.public_server_url) {
      config.hostname = getHostname()
      config.networking_method = NetworkingMethod.Manual
      config.peer_urls.push(config.public_server_url)
    }
    this.configUUIDMap.set(config.instance_id!, config)
    this.configNameUUIDMap.set(config.instance_id!, config.instance_id!)
    this.configUUIDNameMap.set(config.instance_id!, config.instance_id!)
    AppManager.preference.addConfig(config.instance_id!, config.instance_id!, config)
    return true
  }

  public delConfig(uuid: string): boolean {
    if (AppManager.data.favoriteInstance === uuid) {
      AppManager.data.favoriteInstance = undefined
    }
    if (AppManager.easytier.selected === uuid) {
      AppManager.easytier.selected = undefined
    }
    if (this.configUUIDMap.has(uuid)) {
      let name = this.configUUIDNameMap.get(uuid)
      AppManager.preference.configIDPreferences?.deleteSync(uuid)
      AppManager.preference.configIDPreferences?.flushSync()
      AppManager.preference.configPreferences.delete(uuid)
      preferences.deletePreferences(AppManager.content.context!, uuid)
      return this.configUUIDMap.delete(uuid) && this.configNameUUIDMap.delete(name ?? "") &&
      this.configUUIDNameMap.delete(uuid)
    } else {
      return false
    }
  }
}