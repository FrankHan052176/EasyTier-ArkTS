import easytier from 'easytier-ohrs'
import { ConfigJson } from '../../../config/schema/SchemaConfig'
import { VpnExtensionAbilityController } from '../../runtime/VpnExtensionAbilityController'
import { VpnRuntimeStartRequestData } from '../../../infrastructure/bridge/kernel/KernelBridgeTypes'

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
  connectToVpnExtension: (socketName: string, request: VpnRuntimeStartRequestData) => void
  ensureContinuationSocket: () => void
  startEntryRuntime: (cfg: string, uuid: string | undefined, name: string, shouldProtect: boolean) => Promise<boolean>
  sendInvalidConfigToast: () => void
}

export async function orchestrateInstanceStart(options: StartOrchestrationOptions): Promise<boolean> {
  const cfgStr = JSON.stringify(options.config)
  if (!easytier.parseNetworkConfig(cfgStr)) {
    options.sendInvalidConfigToast()
    return false
  }

  let started = false
  if (options.extMode) {
    started = await VpnExtensionAbilityController.start({
      instanceId: options.config.instance_id ?? '',
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
      connectToVpnExtension: options.connectToVpnExtension
    })
  } else {
    const shouldProtect = options.forceGlobal && (options.config.exit_nodes?.length ?? 0) > 0
    started = await options.startEntryRuntime(cfgStr, options.config.instance_id, options.name, shouldProtect)
  }

  if (started && !options.config.no_tun && options.config.instance_id) {
    options.addNeedTun(options.config.instance_id)
  }
  return started
}
