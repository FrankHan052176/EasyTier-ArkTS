import { systemShare } from "@kit.ShareKit";
import { uniformTypeDescriptor } from "@kit.ArkData";
import { Logger } from "../shared/logging/Logger";
import { url } from "@kit.ArkTS";
import { fileIo, fileUri } from '@kit.CoreFileKit'
import { AppManager } from "../AppManager";
import easytier, { SharedConfigLinkPayload } from 'easytier-ohrs';
import { syncWholeConfig } from '../ConfigSyncUtil';
import { ConfigJson } from '../config/schema/SchemaConfig';
import { isCloudResetting } from '../services/cloud/CloudMutationGate';
import { CLOUD_CONFIG_CHANGED_EVENT } from '../ConfigSyncUtil';
import { EventHelper } from './EventHelper';

export function buildShareUrl(config: ConfigJson, callback: (uri: string) => void, only_start: boolean = false,
  name: string | undefined = AppManager.easytier.getConfigName(config.instance_id!) ?? "404") {
  try {
    const displayName = name ?? config.instance_id ?? '404'
    syncWholeConfig(config.instance_id!, displayName, config)
    const uri = easytier.buildConfigShareLink(config.instance_id!, only_start)
    if (uri) {
      callback(uri)
    }
  } catch (e) {
    Logger.error("buildShareUrl error: " + JSON.stringify(e), "ShareUtil")
  }
}

export async function buildShareUrlSync(config: ConfigJson, only_start: boolean = false,
  name: string | undefined = AppManager.easytier.getConfigName(config.instance_id!) ?? "404"): Promise<string> {
  const displayName = name ?? config.instance_id ?? '404'
  syncWholeConfig(config.instance_id!, displayName, config)
  return easytier.buildConfigShareLink(config.instance_id!, only_start) ?? ''
}

export function buildShareData(config: ConfigJson, callback: (data: systemShare.SharedData) => void, only_start: boolean = false,
  name: string | undefined = AppManager.easytier.getConfigName(config.instance_id!) ?? "404", uuid: string | undefined | null = config.instance_id) {
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

export function buildTomlShareData(config: ConfigJson, callback: (data: systemShare.SharedData) => void,
  name: string | undefined = AppManager.easytier.getConfigName(config.instance_id!) ?? '404') {
  try {
    const configId: string | undefined = config.instance_id
    if (!configId) {
      return
    }
    const displayName = name ?? configId
    syncWholeConfig(configId, displayName, config)
    const tomlText = easytier.exportToml(configId)
    if (!tomlText) {
      return
    }

    const filePath = `${AppManager.content.context!.filesDir}/easytier-share.toml`
    try {
      fileIo.unlinkSync(filePath)
    } catch (_) {}

    let file: fileIo.File | null = null
    try {
      file = fileIo.openSync(filePath, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE)
      fileIo.writeSync(file.fd, tomlText)
      fileIo.closeSync(file)
      const shareData: systemShare.SharedData = new systemShare.SharedData({
        utd: uniformTypeDescriptor.UniformDataType.FILE,
        uri: fileUri.getUriFromPath(filePath),
        title: `${displayName}.toml`,
        description: configId
      })
      callback(shareData)
    } catch (err) {
      Logger.error(`buildTomlShareData write error: ${JSON.stringify(err)}`, 'ShareUtil')
      if (file) {
        try {
          fileIo.closeSync(file)
        } catch (_) {}
      }
    }
  } catch (e) {
    Logger.error('buildTomlShareData error: ' + JSON.stringify(e), 'ShareUtil')
  }
}

export async function unwrapUrl(url: url.URL) {
  try {
    if (isCloudResetting()) {
      return
    }
    const payload: SharedConfigLinkPayload | null = easytier.parseConfigShareLink(url.toString())
    if (!payload) {
      return
    }
    const config: ConfigJson = JSON.parse(payload.configJson) as ConfigJson
    const displayName: string = payload.displayName ?? config.instance_id ?? 'shared'
    Logger.debug("unwrap shared config: " + displayName, "ShareUtil")

    if (payload.onlyStart && AppManager.easytier.runningNetworks.size == 0) {
      await AppManager.easytier.temp_start(displayName, config)
      return
    }

    const importedId: string | null = easytier.importConfigShareLink(url.toString(), payload.displayName)
    if (importedId) {
      EventHelper.emitterPublish(CLOUD_CONFIG_CHANGED_EVENT)
    }
    const storedJson = importedId ? easytier.getConfig(importedId) : undefined
    const importedConfig: ConfigJson = storedJson ? JSON.parse(storedJson) as ConfigJson : config
    const finalId: string = importedId ?? importedConfig.instance_id!
    AppManager.data.readConfig(finalId, payload.displayName ?? finalId, importedConfig)
  } catch (e) {
    Logger.error("unwrapUrl error: " + JSON.stringify(e), "ShareUtil")
  }
}
