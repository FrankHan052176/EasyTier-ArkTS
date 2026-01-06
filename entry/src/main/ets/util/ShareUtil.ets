import { compressStr, uncompressStr } from "../CompressUtil";
import { mappedJson, unmappedJson } from "../MappedUtil";
import { NetworkConfig } from "../protobuf/api_manage";
import { systemShare } from "@kit.ShareKit";
import { uniformTypeDescriptor } from "@kit.ArkData";
import { Logger } from "./Logger";
import { url } from "@kit.ArkTS";
import { AppManager } from "../AppManager";

export function buildShareData(config: NetworkConfig, callback: (data: systemShare.SharedData) => void,
  name: string | undefined, uuid: string | undefined | null = config.instance_id) {
  compressStr(mappedJson(config)).then((data) => {
    let urlName = name?("&name="+name):""
    try {
      let shareData: systemShare.SharedData = new systemShare.SharedData({
        utd: uniformTypeDescriptor.UniformDataType.HYPERLINK,
        content: 'https://easytier.cn/comp_cfg?cfg=' + data+urlName,
        title: '分享配置 ' + (name ?? ""),
        description: uuid ?? ""
      });
      callback(shareData);
    } catch (e) {
      Logger.error("systemShare" + JSON.stringify(e), "ShareUtil")
    }
  }).catch((e: Error) => {
    Logger.error("compressedConfig" + JSON.stringify(e), "ShareUtil")
  })
}

export async function unwrapUrl(url: url.URL) {
  let cfg = url.params.get("cfg")
  let name = url.params.get("name")
  Logger.debug("get Cfg "+name+": " + cfg, "ShareUtil")
  if (cfg) {
    let config = unmappedJson(await uncompressStr(cfg))
    config.instance_id = AppManager.data.safeUUID()
    AppManager.data.readConfig(config.instance_id!, name?name:config.instance_id!, config)
  }
}