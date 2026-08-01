import { Want } from '@kit.AbilityKit'
import { vpnExtension } from '@kit.NetworkKit'
import { VpnRuntimeStartRequestData } from '../../infrastructure/bridge/kernel/KernelBridgeTypes'
import { APP_BUNDLE_NAME, VPN_EXTENSION_ABILITY_NAME, VPN_EXTENSION_SOCKET_NAME } from './AbilityRuntimePolicy'
import { Logger } from '../../shared/logging/Logger'

export interface VpnExtensionStartOptions {
  instanceId: string
  cfg: string
  name: string
  socketFilesDir: string
  vpnRoutes: boolean
  whiteList: boolean
  blackList: string[]
  dns: string
  dev: boolean
  forceGlobal: boolean
  coreLog: boolean
  debugLog: boolean
  ensureContinuationSocket: () => void
  connectToVpnExtension: (socketName: string, request: VpnRuntimeStartRequestData) => void
}

let extensionOperationQueue: Promise<void> = Promise.resolve()
let extensionStartedByController: boolean = false

function enqueueExtensionOperation(action: () => Promise<void>): Promise<void> {
  const operation = extensionOperationQueue.catch(() => {}).then(action)
  extensionOperationQueue = operation.catch(() => {})
  return operation
}

export class VpnExtensionAbilityController {
  static start(options: VpnExtensionStartOptions): Promise<boolean> {
    const startRequest: VpnRuntimeStartRequestData = {
      instanceId: options.instanceId,
      cfg: options.cfg,
      name: options.name,
      socketFilesDir: options.socketFilesDir,
      vpnRoutes: options.vpnRoutes,
      whiteList: options.whiteList,
      blackList: options.blackList,
      dns: options.dns,
      dev: options.dev,
      forceGlobal: options.forceGlobal,
      coreLog: options.coreLog,
      debugLog: options.debugLog
    }
    const want: Want = {
      deviceId: '',
      bundleName: APP_BUNDLE_NAME,
      abilityName: VPN_EXTENSION_ABILITY_NAME,
      parameters: {
        instance_id: startRequest.instanceId,
        cfg: startRequest.cfg,
        name: startRequest.name,
        socket: VPN_EXTENSION_SOCKET_NAME,
        socket_files_dir: startRequest.socketFilesDir,
        vpn_routes: startRequest.vpnRoutes,
        white_list: startRequest.whiteList,
        black_list: startRequest.blackList,
        dns: startRequest.dns,
        dev: startRequest.dev,
        force_global: startRequest.forceGlobal,
        core_log: startRequest.coreLog,
        debug_log: startRequest.debugLog
      }
    }
    options.ensureContinuationSocket()
    let started = false
    return enqueueExtensionOperation(async () => {
      if (extensionStartedByController) {
        Logger.warn('cleaning stale VPN extension before a new start', 'VpnExtensionAbilityController')
        try {
          await vpnExtension.stopVpnExtensionAbility({
            deviceId: '',
            bundleName: APP_BUNDLE_NAME,
            abilityName: VPN_EXTENSION_ABILITY_NAME
          })
        } catch (error) {
          const err = error as Error
          Logger.warn(`stale VPN extension cleanup returned error: ${err.message}`, 'VpnExtensionAbilityController')
        } finally {
          extensionStartedByController = false
        }
      }
      try {
        await vpnExtension.startVpnExtensionAbility(want)
        extensionStartedByController = true
        options.connectToVpnExtension(VPN_EXTENSION_SOCKET_NAME, startRequest)
        started = true
      } catch (error) {
        const err = error as Error
        extensionStartedByController = false
        Logger.error(`start VPN extension failed: ${err.message}`, 'VpnExtensionAbilityController')
      }
    }).then(() => started)
  }

  static stop(waitForStopped?: () => Promise<void>): Promise<void> {
    const want: Want = {
      deviceId: '',
      bundleName: APP_BUNDLE_NAME,
      abilityName: VPN_EXTENSION_ABILITY_NAME
    }
    return enqueueExtensionOperation(async () => {
      try {
        await vpnExtension.stopVpnExtensionAbility(want)
        if (waitForStopped) {
          await waitForStopped()
        }
      } finally {
        extensionStartedByController = false
      }
    })
  }
}
