import easytier from 'easytier-ohrs'
import { ConfigJson } from '../../../config/schema/SchemaConfig'
import { VpnExtensionAbilityController } from '../../runtime/VpnExtensionAbilityController'

export interface StartOrchestrationOptions {
  config: ConfigJson
  configRootDir: string
  socketFilesDir: string
  addNeedTun: (instanceId: string) => void
  connectToVpnExtension: (socketName: string) => void
  isVpnExtensionConnected: () => boolean
  ensureContinuationSocket: () => void
  sendInvalidConfigToast: () => void
}

export async function orchestrateInstanceStart(options: StartOrchestrationOptions): Promise<boolean> {
  const cfgStr = JSON.stringify(options.config)
  if (!easytier.parseNetworkConfig(cfgStr)) {
    options.sendInvalidConfigToast()
    return false
  }
  const instanceValue = options.config.instance_id as string | undefined
  const instanceId: string = instanceValue ?? ''
  if (instanceId.length === 0) {
    options.sendInvalidConfigToast()
    return false
  }
  const extensionReady = await VpnExtensionAbilityController.start({
    configRootDir: options.configRootDir,
    socketFilesDir: options.socketFilesDir,
    ensureContinuationSocket: options.ensureContinuationSocket,
    connectToVpnExtension: options.connectToVpnExtension,
    isConnected: options.isVpnExtensionConnected
  })
  if (extensionReady && !options.config.no_tun) {
    options.addNeedTun(instanceId)
  }
  return extensionReady
}
