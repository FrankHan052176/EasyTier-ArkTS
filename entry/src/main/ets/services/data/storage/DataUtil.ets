import { Logger, LogLocate } from '../../../shared/logging/Logger';
import { util } from '@kit.ArkTS';
import { FieldValueDataSource } from '../../../class/FieldValueDataSource';
import { Url } from '../../../class/config/Url';
import { AppManager } from '../../../AppManager';
import { getDefaultConfig } from '../../../config/defaults/ConfigDefaults';
import { getHostname } from '../../../util/Conversion';
import { deviceInfo } from '@kit.BasicServicesKit';
import { FieldValue } from '../../../class/config/Basic';
import { Cidr } from '../../../class/config/Cidr';
import { PortForward } from '../../../class/config/PortForward';
import { NetworkName } from '../../../class/config/NetworkName';
import { IP } from '../../../class/config/IP';
import { HMRouterTransitions } from '@hadss/hmrouter-transitions';
import { HMRouterMgr } from '@hadss/hmrouter';
import easytier from 'easytier-ohrs';
import { ConfigJson } from '../../../config/schema/SchemaConfig';
import { syncWholeConfig } from '../../../ConfigSyncUtil';

interface StoredConfigMetaLite {
  configId: string
}

@LogLocate("DataUtil")
@ObservedV2
export class DataUtil {
  @Trace globalDataMap: Map<string, FieldValueDataSource> = new Map
  @Trace configIds: string[] = []

  refreshConfigIds(): void {
    try {
      const stored = JSON.parse(easytier.listConfigs()) as StoredConfigMetaLite[]
      this.configIds = (stored ?? []).map((item) => item.configId)
      if (AppManager.uiState.selected && !this.configIds.includes(AppManager.uiState.selected)) {
        AppManager.uiState.selected = this.configIds.length > 0 ? this.configIds[0] : undefined
      }
      if (AppManager.uiState.favorite && !this.configIds.includes(AppManager.uiState.favorite)) {
        AppManager.uiState.favorite = undefined
      }
    } catch (_) {
      this.configIds = []
      AppManager.uiState.selected = undefined
      AppManager.uiState.favorite = undefined
    }
  }

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
    this.refreshConfigIds()
  }

  public safeUUID(): string {
    let uuid = util.generateRandomUUID()
    while (AppManager.easytier.getConfig(uuid)) {
      uuid = util.generateRandomUUID()
    }
    return uuid
  }

  public newConfig(name: string): ConfigJson {
    let config: ConfigJson = getDefaultConfig(getHostname())
    config.instance_id = this.safeUUID()
    syncWholeConfig(config.instance_id, name, config)
    this.refreshConfigIds()
    const animator = HMRouterTransitions.cardLongTake("instance_card_" + config.instance_id, "edit_content");
    AppManager.uiState.selected = config.instance_id
    AppManager.uiState.editingInstance = config.instance_id
    HMRouterMgr.push({ pageUrl: 'EditPage', param: {uuid:config.instance_id, unsafe: false}, animator: animator });
    return config
  }

  public readConfig(uuid: string, name: string, config: ConfigJson): ConfigJson {
    this.refreshConfigIds()
    AppManager.uiState.editingInstance = uuid
    HMRouterMgr.push({ pageUrl: 'EditPage', param: { uuid, unsafe: false } })
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
    let config: ConfigJson
    try {
      config = JSON.parse(cfg)
    } catch (e) {
      Logger.error(`importToml parse error: ${JSON.stringify(e)}`, this)
      return false
    }
    if ((config.networking_method as number | undefined) === 0 && config.public_server_url) {
      config.hostname = getHostname()
      config.networking_method = 1
      config.peer_urls.push(config.public_server_url)
    }
    config.proxy_cidrs.forEach((cidrStr: string): void => {
      let cidr = new Cidr()
      if (cidr.fromString(cidrStr)) {
        this.getDataSource("cidr").add(cidr)
      }
    })
    config.routes.forEach((routeStr: string): void => {
      let route = new Cidr()
      if (route.fromString(routeStr)) {
        this.getDataSource("route").add(route)
      }
    })
    config.peer_urls.forEach((urlStr: string): void => {
      let url = new Url()
      if (url.fromString(urlStr)) {
        this.getDataSource("peer").add(url)
      }
    })
    config.listener_urls.forEach((urlStr: string): void => {
      let url = new Url()
      if (url.fromString(urlStr)) {
        this.getDataSource("listener").add(url)
      }
    })
    config.mapped_listeners.forEach((urlStr: string): void => {
      let url = new Url()
      if (url.fromString(urlStr)) {
        this.getDataSource("mapped_listener").add(url)
      }
    })
    config.exit_nodes.forEach((nodeStr: string): void => {
      let ip = new IP()
      if (ip.fromString(nodeStr)) {
        this.getDataSource("ip").add(ip)
      }
    })
    config.relay_network_whitelist.forEach((wlStr: string): void => {
      let name = new NetworkName()
      if (name.fromString(wlStr)) {
        this.getDataSource("network_name").add(name)
      }
    })
    config.port_forwards.forEach((pfConfig: ESObject): void => {
      let pf = new PortForward()
      if (pf.readFrom(pfConfig)) {
        this.getDataSource("port_forward").add(pf)
      }
    })
    syncWholeConfig(config.instance_id!, name ?? config.instance_id!, config)
    this.refreshConfigIds()
    const animator = HMRouterTransitions.cardLongTake("instance_card_" + config.instance_id, "edit_content");
    AppManager.uiState.selected = config.instance_id
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
    if (AppManager.easytier.getConfig(uuid)) {
      easytier.deleteStoredConfigMeta(uuid)
      this.refreshConfigIds()
      return true
    } else {
      return false
    }
  }
}
