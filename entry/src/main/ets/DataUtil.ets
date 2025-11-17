import { distributedKVStore } from "@kit.ArkData";
import { ContextUtil } from "./ContextUtil";
import { Logger } from "./util/Logger";
import { JSON } from "@kit.ArkTS";
import { FieldValueDataSource } from "./class/FieldValueDataSource";
import { Cidr } from "./class/config/Cidr";
import { Url } from "./class/config/Url";
import { IP } from "./class/config/IP";
import { NetworkName } from "./class/config/NetworkName";
import { PortForward } from "./class/config/PortForward";

@ObservedV2
export class DataUtil {
  public static globalDataMap: Map<string, FieldValueDataSource> = new Map

  public static getDataSource(type: string): FieldValueDataSource {
    if (DataUtil.globalDataMap.has(type)) {
      return DataUtil.globalDataMap.get(type)!
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
      DataUtil.globalDataMap.set(type, dataSource)
      return dataSource
    }
  }

  public static init() {
    let kvManager: distributedKVStore.KVManager | undefined = undefined;
    try {
      const kvManagerConfig: distributedKVStore.KVManagerConfig = {
        bundleName: 'top.frankhan.easytier',
        context: ContextUtil.context!,
      }
      kvManager = distributedKVStore.createKVManager(kvManagerConfig);
    } catch (e) {
      Logger.info(`Failed to create KVManager. \n${JSON.stringify(e)}`);
    }
  }
}