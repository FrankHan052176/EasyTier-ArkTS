import { compressStr } from "../CompressUtil";
import { mappedJson } from "../MappedUtil";
import { NetworkConfig } from "../protobuf/api_manage";
import { systemShare } from "@kit.ShareKit";
import { uniformTypeDescriptor } from "@kit.ArkData";
import { Logger } from "./Logger";

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