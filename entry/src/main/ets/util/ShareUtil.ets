import { compressStr, uncompressStr } from "../CompressUtil";
import { mappedJson, unmappedJson } from "../MappedUtil";
import { NetworkConfig } from "../protobuf/api_manage";
import { systemShare } from "@kit.ShareKit";
import { uniformTypeDescriptor } from "@kit.ArkData";
import { Logger } from "./Logger";
import { url } from "@kit.ArkTS";
import { AppManager } from "../AppManager";
import { getHostname } from "./Conversion";

export function buildShareUrl(config: NetworkConfig, callback: (uri: string) => void, only_start: boolean = false,
  name: string | undefined = AppManager.uiState.configUUIDNameMap.get(config.instance_id!) ?? "404") {
  compressStr(mappedJson(config)).then((data) => {
    let urlName = name?("&name="+name):""
    callback('https://easytier.cn/comp_cfg?cfg=' + data + urlName + (only_start?"&only_start=true":""))
  }).catch((e: Error) => {
    Logger.error("compressedConfig" + JSON.stringify(e), "ShareUtil")
  })
}

export async function buildShareUrlSync(config: NetworkConfig, only_start: boolean = false,
  name: string | undefined = AppManager.uiState.configUUIDNameMap.get(config.instance_id!) ?? "404"): Promise<string> {
  let data = await compressStr(mappedJson(config))
  let urlName = name?("&name="+name):""
  return 'https://easytier.cn/comp_cfg?cfg=' + data + urlName + (only_start?"&only_start=true":"")
}

export function buildShareData(config: NetworkConfig, callback: (data: systemShare.SharedData) => void, only_start: boolean = false,
  name: string | undefined = AppManager.uiState.configUUIDNameMap.get(config.instance_id!) ?? "404", uuid: string | undefined | null = config.instance_id) {
  buildShareUrl(config, (url) => {
    try {
      let shareData: systemShare.SharedData = new systemShare.SharedData({
        utd: uniformTypeDescriptor.UniformDataType.HYPERLINK,
        content: url,
        title: '分享配置 ' + (name ?? ""),
        description: uuid ?? ""
      });
      callback(shareData);
    } catch (e) {
      Logger.error("systemShare" + JSON.stringify(e), "ShareUtil")
    }
  }, only_start, name)
}

export async function unwrapUrl(url: url.URL) {
  let cfg = url.params.get("cfg")
  let name = url.params.get("name")
  let only_start = url.params.get("only_start")
  Logger.debug("get Cfg "+name+": " + cfg, "ShareUtil")
  if (cfg) {
    let config = unmappedJson(await uncompressStr(cfg))
    config.instance_id = AppManager.data.safeUUID()
    config.hostname = getHostname()
    AppManager.data.tempConfigMap.set(config.instance_id!, config)
    if (only_start && AppManager.easytier.runningNetworks.size == 0) {
      AppManager.easytier.temp_start(name?name:config.instance_id!, config)
    }else {
      AppManager.data.readConfig(config.instance_id!, name?name:config.instance_id!, config)
    }
  }
}