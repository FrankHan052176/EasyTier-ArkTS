import { Want, common } from '@kit.AbilityKit'
import { vpnExtension } from '@kit.NetworkKit'
import easytier from 'easytier-ohrs'
import { ConfigJson } from '../../../config/schema/SchemaConfig'

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
  showLog: boolean
  addNeedTun: (instanceId: string) => void
  connectToVpnExtension: (socketName: string) => void
  ensureContinuationSocket: () => void
  requestVpnPerm: (callback: () => void) => void
  requestLocPerm: () => Promise<boolean>
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
    const want: Want = {
      bundleName: 'top.frankhan.easytier',
      abilityName: 'EasyTierAbility',
      parameters: {
        cfg: cfgStr,
        name: options.name,
        socket: 'easytier_vpn_socket',
        socket_files_dir: options.socketFilesDir,
        vpn_routes: options.vpnRoutes,
        white_list: options.whiteList,
        black_list: options.blackList,
        dns: options.dns,
        dev: options.dev,
        force_global: options.forceGlobal,
        show_log: options.showLog
      }
    }
    options.ensureContinuationSocket()
    options.requestVpnPerm(() => {
      vpnExtension.startVpnExtensionAbility(want)
      options.connectToVpnExtension('easytier_vpn_socket')
    })
  } else {
    options.requestLocPerm().then(() => {
      options.publishStartBg(cfgStr, options.config.instance_id, options.name)
    })
  }

  return true
}
