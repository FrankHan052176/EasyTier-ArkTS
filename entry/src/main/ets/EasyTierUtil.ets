import entry from 'libentry.so'
import { NetworkInstanceRunningInfo } from './protobuf/api_manage'
import easytier from "easytier-ohrs"
import { EventHelper } from './util/EventHelper'

@ObservedV2
export class EasyTierUtil {
  @Trace appLogs: Set<string> = new Set
  @Trace nmLogs: Set<string> = new Set
  @Trace ohLogs: Set<string> = new Set
  @Trace runningNetworks: Map<string, NetworkInstanceRunningInfo> = new Map

  init() {
    setInterval(() => {
      this.readLogs()
    }, 500)
  }

  private readInfo() {
    let infos = easytier.collectNetworkInfos()
    let networks = new Set<string>
    for (const info of infos) {
      networks.add(info.key)
      let newInfo: NetworkInstanceRunningInfo = JSON.parse(info.value)
      this.runningNetworks.set(info.key, newInfo)
      EventHelper.emitterPublish("updateInfo_"+info.key, {
        data:  {
          info: newInfo
        }
      })
    }
    for (const pair of Array.from(this.runningNetworks.keys())) {
      if (!networks.has(pair[0])) {
        this.runningNetworks.delete(pair[0])
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
}