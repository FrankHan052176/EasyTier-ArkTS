import entry from 'libentry.so'
import { NetworkInstanceRunningInfo } from './protobuf/api_manage'
import easytier from "easytier-ohrs"
import { EventHelper } from './util/EventHelper'

@ObservedV2
export class EasyTierUtil {
  @Trace public static appLogs: Set<string> = new Set
  @Trace public static nmLogs: Set<string> = new Set
  @Trace public static ohLogs: Set<string> = new Set
  @Trace public static runningNetworks: Map<string, NetworkInstanceRunningInfo> = new Map

  private static readInfo() {
    let infos = easytier.collectNetworkInfos()
    let networks = new Set<string>
    for (const info of infos) {
      networks.add(info.key)
      let newInfo: NetworkInstanceRunningInfo = JSON.parse(info.value)
      EasyTierUtil.runningNetworks.set(info.key, newInfo)
      EventHelper.emitterPublish("updateInfo_"+info.key, {
        data:  {
          info: newInfo
        }
      })
    }
    for (const pair of Array.from(EasyTierUtil.runningNetworks.keys())) {
      if (!networks.has(pair[0])) {
        EasyTierUtil.runningNetworks.delete(pair[0])
      }
    }
  }

  private static readLogs() {
    let appLogs = entry.getAppLog()
    if (EasyTierUtil.appLogs.size < appLogs.length) {
      appLogs.forEach((value) => {
        EasyTierUtil.appLogs.add(value)
      })
    }
    let nmLogs = entry.getNetworkManagerLog()
    if (EasyTierUtil.nmLogs.size < nmLogs.length) {
      nmLogs.forEach((value) => {
        EasyTierUtil.nmLogs.add(value)
      })
    }
    let ohLogs = entry.getOHLog()
    if (EasyTierUtil.ohLogs.size < ohLogs.length) {
      ohLogs.forEach((value) => {
        EasyTierUtil.ohLogs.add(value)
      })
    }
  }
}