import { Want } from '@kit.AbilityKit'
import { vpnExtension } from '@kit.NetworkKit'

const VPN_EXTENSION_SOCKET_NAME = 'easytier_vpn_socket'
const EASYTIER_BUNDLE_NAME = 'top.frankhan.easytier'
const EASYTIER_VPN_ABILITY_NAME = 'EasyTierAbility'

export interface VpnExtensionStartOptions {
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
  requestVpnPerm: (callback: () => void) => void
  connectToVpnExtension: (socketName: string) => void
}

export class VpnExtensionAbilityController {
  static start(options: VpnExtensionStartOptions): void {
    const want: Want = {
      bundleName: EASYTIER_BUNDLE_NAME,
      abilityName: EASYTIER_VPN_ABILITY_NAME,
      parameters: {
        cfg: options.cfg,
        name: options.name,
        socket: VPN_EXTENSION_SOCKET_NAME,
        socket_files_dir: options.socketFilesDir,
        vpn_routes: options.vpnRoutes,
        white_list: options.whiteList,
        black_list: options.blackList,
        dns: options.dns,
        dev: options.dev,
        force_global: options.forceGlobal,
        core_log: options.coreLog,
        debug_log: options.debugLog
      }
    }
    options.ensureContinuationSocket()
    options.requestVpnPerm(() => {
      vpnExtension.startVpnExtensionAbility(want)
      options.connectToVpnExtension(VPN_EXTENSION_SOCKET_NAME)
    })
  }

  static stop(): void {
    const want: Want = {
      bundleName: EASYTIER_BUNDLE_NAME,
      abilityName: EASYTIER_VPN_ABILITY_NAME
    }
    vpnExtension.stopVpnExtensionAbility(want)
  }
}
