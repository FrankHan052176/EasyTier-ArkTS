import { distributedKVStore } from "@kit.ArkData";
import { Logger, LogLocate } from "./util/Logger";
import { JSON, util } from "@kit.ArkTS";
import { FieldValueDataSource } from "./class/FieldValueDataSource";
import { Cidr } from "./class/config/Cidr";
import { Url } from "./class/config/Url";
import { IP } from "./class/config/IP";
import { NetworkName } from "./class/config/NetworkName";
import { PortForward } from "./class/config/PortForward";
import { NetworkConfig } from "./protobuf/api_manage";
import { ContentUtil } from "./ContentUtil";
import { AppManager } from "./AppManager";
import { EventHelper } from "./util/EventHelper";

@LogLocate("DataUtil")
@ObservedV2
export class DataUtil {
  @Trace globalDataMap: Map<string, FieldValueDataSource> = new Map
  @Trace configUUIDMap: Map<string, NetworkConfig> = new Map
  @Trace configNameUUIDMap: Map<string, string> = new Map
  @Trace configUUIDNameMap: Map<string, string> = new Map
  @Trace favoriteInstance: string | undefined

  public isFavorite(uuid: string) {
    return this.favoriteInstance !== undefined && uuid === this.favoriteInstance
  }

  public changeFavorite(uuid: string) {
    if (this.isFavorite(uuid)) {
      this.favoriteInstance = undefined
    }else {
      this.favoriteInstance = uuid
    }
    EventHelper.emitterPublish("favorite_update")
  }

  public getDataSource(type: string): FieldValueDataSource {
    if (this.globalDataMap.has(type)) {
      return this.globalDataMap.get(type)!
    }else {
      let dataSource = new FieldValueDataSource()
      if (type === "cidr" || type === "route") {
        dataSource.add(new Cidr())
      }else if (type === "peer" || type === "listener" || type === "mappedListener") {
        dataSource.add(new Url())
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
    let kvManager: distributedKVStore.KVManager | undefined = undefined;
    try {
      const kvManagerConfig: distributedKVStore.KVManagerConfig = {
        bundleName: 'top.frankhan.easytier',
        context: AppManager.content.context!,
      }
      kvManager = distributedKVStore.createKVManager(kvManagerConfig);
    } catch (e) {
      Logger.info(`Failed to create KVManager. \n${JSON.stringify(e)}`, DataUtil);
    }
    this.favoriteInstance = this.newConfig("测试Ⅰ").instanceId
    this.newConfig("测试Ⅱ")
    this.newConfig("测试Ⅲ")
  }

  public safeUUID(): string {
    let uuid = util.generateRandomUUID()
    while (this.configUUIDMap.has(uuid)) {
      uuid = util.generateRandomUUID()
    }
    return uuid
  }

  public newConfig(name: string): NetworkConfig {
    let config = ContentUtil.getDefaultConfig()
    config.instanceId = this.safeUUID()
    this.configUUIDMap.set(config.instanceId, config)
    this.configNameUUIDMap.set(name, config.instanceId)
    this.configUUIDNameMap.set(config.instanceId, name)
    return config
  }
}