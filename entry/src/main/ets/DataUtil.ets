import { Logger, LogLocate } from "./util/Logger";
import { util } from "@kit.ArkTS";
import { FieldValueDataSource } from "./class/FieldValueDataSource";
import { Cidr } from "./class/config/Cidr";
import { Url } from "./class/config/Url";
import { IP } from "./class/config/IP";
import { NetworkName } from "./class/config/NetworkName";
import { PortForward } from "./class/config/PortForward";
import { NetworkConfig } from "./protobuf/api_manage";
import { ContentUtil } from "./ContentUtil";
import { AppManager } from "./AppManager";
import { getHostname } from "./util/Conversion";
import { preferences } from "@kit.ArkData";

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
    }else {
      this.favoriteInstance = uuid
    }
  }

  public getDataSource(type: string): FieldValueDataSource {
    if (this.globalDataMap.has(type)) {
      return this.globalDataMap.get(type)!
    }else {
      let dataSource = new FieldValueDataSource()
      if (type === "cidr" || type === "route") {
        dataSource.add(new Cidr())
      }else if (type === "peer") {
        dataSource.add(new Url())
      }else if (type === "listener" || type === "mappedListener") {
        let value = new Url()
        value.domain = "0.0.0.0"
        dataSource.add(value)
      }else if (type === "ip") {
        dataSource.add(new IP())
      }else if (type === "string") {
        dataSource.add(new NetworkName())
      }else if (type === "port_forward") {
        dataSource.add(new PortForward())
      }
      this.globalDataMap.set(type, dataSource)
      return dataSource
    }
  }

  public init() {
    // this.favoriteInstance = this.newConfig("测试Ⅰ").instance_id
    // this.newConfig("测试Ⅱ")
    // this.newConfig("测试Ⅲ")
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

  public readConfig(uuid:string, name: string, config: NetworkConfig) {
    this.configUUIDMap.set(uuid, config)
    this.configNameUUIDMap.set(name, uuid)
    this.configUUIDNameMap.set(uuid, name)
    return config
  }

  public delConfig(uuid: string): boolean {
    if (AppManager.data.favoriteInstance === uuid) {
      AppManager.data.favoriteInstance = undefined
    }
    if (this.configUUIDMap.has(uuid)) {
      let name = this.configUUIDNameMap.get(uuid)
      preferences.deletePreferences(AppManager.content.context!, uuid)
      AppManager.preference.configIDPreferences?.deleteSync(uuid)
      AppManager.preference.configPreferences.delete(uuid)
      AppManager.preference.configIDPreferences?.flushSync()
      return this.configUUIDMap.delete(uuid) && this.configNameUUIDMap.delete(name ?? "") && this.configUUIDNameMap.delete(uuid)
    }else {
      return false
    }
  }
}