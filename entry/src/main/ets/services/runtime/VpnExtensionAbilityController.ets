import { Want } from '@kit.AbilityKit'
import { vpnExtension } from '@kit.NetworkKit'
import { APP_BUNDLE_NAME, VPN_EXTENSION_ABILITY_NAME, VPN_EXTENSION_SOCKET_NAME } from './AbilityRuntimePolicy'
import { Logger } from '../../shared/logging/Logger'

export interface VpnExtensionStartOptions {
  configRootDir: string
  socketFilesDir: string
  ensureContinuationSocket: () => void
  connectToVpnExtension: (socketName: string) => void
  isConnected: () => boolean
}

let extensionOperationQueue: Promise<void> = Promise.resolve()

function enqueueExtensionOperation(action: () => Promise<void>): Promise<void> {
  const operation = extensionOperationQueue.catch(() => {}).then(action)
  extensionOperationQueue = operation.catch(() => {})
  return operation
}

export class VpnExtensionAbilityController {
  static start(options: VpnExtensionStartOptions): Promise<boolean> {
    options.ensureContinuationSocket()
    if (options.isConnected()) {
      return Promise.resolve(true)
    }
    const want: Want = {
      deviceId: '',
      bundleName: APP_BUNDLE_NAME,
      abilityName: VPN_EXTENSION_ABILITY_NAME,
      parameters: {
        config_root_dir: options.configRootDir,
        socket_files_dir: options.socketFilesDir,
        socket: VPN_EXTENSION_SOCKET_NAME
      }
    }
    let started = false
    return enqueueExtensionOperation(async () => {
      if (options.isConnected()) {
        started = true
        return
      }
      try {
        await vpnExtension.startVpnExtensionAbility(want)
        options.connectToVpnExtension(VPN_EXTENSION_SOCKET_NAME)
        started = true
      } catch (error) {
        const err = error as Error
        Logger.error(`start VPN extension failed: ${err.message}`, 'VpnExtensionAbilityController')
      }
    }).then(() => started)
  }
}
