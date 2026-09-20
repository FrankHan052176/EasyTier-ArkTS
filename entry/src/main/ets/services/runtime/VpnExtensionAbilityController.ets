import { Want } from '@kit.AbilityKit'
import { vpnExtension } from '@kit.NetworkKit'
import { fileIo } from '@kit.CoreFileKit'
import { APP_BUNDLE_NAME, VPN_EXTENSION_ABILITY_NAME, VPN_EXTENSION_SOCKET_NAME } from './AbilityRuntimePolicy'
import { Logger } from '../../shared/logging/Logger'
import { RuntimeHostLease } from './RuntimeHostLease'

export interface VpnExtensionStartOptions {
  configRootDir: string
  socketFilesDir: string
  ensureContinuationSocket: () => Promise<boolean>
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
      if (!await options.ensureContinuationSocket()) {
        return
      }
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

  static stop(socketFilesDir: string): Promise<void> {
    return enqueueExtensionOperation(async () => {
      const socketPath = `${socketFilesDir}/${VPN_EXTENSION_SOCKET_NAME}`
      const want: Want = {
        bundleName: APP_BUNDLE_NAME,
        abilityName: VPN_EXTENSION_ABILITY_NAME
      }
      if (fileIo.accessSync(socketPath)) {
        await vpnExtension.stopVpnExtensionAbility(want)
      }
      const deadline = Date.now() + 5000
      while (fileIo.accessSync(socketPath) || !RuntimeHostLease.isAvailable(socketFilesDir)) {
        if (Date.now() >= deadline) {
          throw new Error('VPN extension resource cleanup timed out')
        }
        await new Promise<void>((resolve) => setTimeout(resolve, 25))
      }
    })
  }
}
