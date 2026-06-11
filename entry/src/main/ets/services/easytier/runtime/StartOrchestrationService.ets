import easytier from 'easytier-ohrs'
import { ConfigJson } from '../../../config/schema/SchemaConfig'
import { VpnExtensionAbilityController } from '../../runtime/VpnExtensionAbilityController'

export interface StartOrchestrationOptions {
  config: ConfigJson
  name: string
  extMode: boolean
  socketFilesDir: string
  vpnRoutes: boolean
  whiteList: boolean
  blackList: string[]
  dns: string
  dev: boolean
  forceGlobal: boolean
  coreLog: boolean
  debugLog: boolean
  addNeedTun: (instanceId: string) => void
  connectToVpnExtension: (socketName: string) => void
  ensureContinuationSocket: () => void
  requestVpnPerm: (callback: () => void) => void
  publishStartBg: (cfg: string, uuid: string | undefined, name: string) => void
  sendInvalidConfigToast: () => void
}

export function orchestrateInstanceStart(options: StartOrchestrationOptions): boolean {
  const cfgStr = JSON.stringify(options.config)
  if (!easytier.parseNetworkConfig(cfgStr)) {
    options.sendInvalidConfigToast()
    return true
  }

  if (!options.config.no_tun && options.config.instance_id) {
    options.addNeedTun(options.config.instance_id)
  }

  if (options.extMode) {
    VpnExtensionAbilityController.start({
      cfg: cfgStr,
      name: options.name,
      socketFilesDir: options.socketFilesDir,
      vpnRoutes: options.vpnRoutes,
      whiteList: options.whiteList,
      blackList: options.blackList,
      dns: options.dns,
      dev: options.dev,
      forceGlobal: options.forceGlobal,
      coreLog: options.coreLog,
      debugLog: options.debugLog,
      ensureContinuationSocket: options.ensureContinuationSocket,
      requestVpnPerm: options.requestVpnPerm,
      connectToVpnExtension: options.connectToVpnExtension
    })
  } else {
    options.publishStartBg(cfgStr, options.config.instance_id, options.name)
  }

  return true
}
