import { common } from '@kit.AbilityKit'
import { BusinessError } from '@kit.BasicServicesKit'
import { vpnExtension } from '@kit.NetworkKit'
import { Logger } from '../../shared/logging/Logger'
import { shouldBuildPreferenceVpnRoutes, buildTunVpnConfig } from './TunConfigBuilder'

export interface EntryVpnSetupRequest {
  ip: string
  mask: number
  magicDNS: boolean
  instanceId: string
  needExitNode: boolean
  routes?: string[]
  vpnRoutes: boolean
  whiteList: boolean
  blackList: string[]
  dev: boolean
  dns: string
}

export interface EntryVpnConnectionServiceOptions {
  context: common.UIAbilityContext
  logTarget: Object | string
  requestVpnPerm: (callback: () => void) => void
  activateMissionContinue: () => void
  setTunFd: (instanceId: string, fd: number) => void
}

export class EntryVpnConnectionService {
  private readonly context: common.UIAbilityContext
  private readonly logTarget: Object | string
  private readonly requestVpnPerm: (callback: () => void) => void
  private readonly activateMissionContinue: () => void
  private readonly setTunFd: (instanceId: string, fd: number) => void
  private vpnConnection: vpnExtension.VpnConnection | undefined = undefined

  constructor(options: EntryVpnConnectionServiceOptions) {
    this.context = options.context
    this.logTarget = options.logTarget
    this.requestVpnPerm = options.requestVpnPerm
    this.activateMissionContinue = options.activateMissionContinue
    this.setTunFd = options.setTunFd
  }

  prepareVpn(shouldProtect: boolean = false, callback: () => void = () => {}): void {
    if (this.vpnConnection !== undefined) {
      Logger.info('prepare_vpn reuse existing vpnConnection', this.logTarget)
      if (shouldProtect) {
        this.vpnConnection.protectProcessNet().then(() => {
          Logger.info('protectProcessNet completed before kernel start', this.logTarget)
          callback()
        }).catch((error: BusinessError) => {
          Logger.error(`protectProcessNet failed: ${error.code}, ${error.message}`, this.logTarget)
          callback()
        })
        return
      }
      callback()
      return
    }
    Logger.info('prepare vpn', this.logTarget)
    this.requestVpnPerm(async () => {
      this.vpnConnection = vpnExtension.createVpnConnection(this.context as Object as vpnExtension.VpnExtensionContext)
      Logger.info('vpnConnection created in prepare_vpn', this.logTarget)
      if (shouldProtect) {
        await this.vpnConnection?.protectProcessNet()
        Logger.info('protectProcessNet completed before kernel start', this.logTarget)
      }
      callback()
    })
  }

  async setupTun(request: EntryVpnSetupRequest): Promise<void> {
    Logger.info(`setup_tun start instance=${request.instanceId} ip=${request.ip}/${request.mask} magicDNS=${request.magicDNS} needExitNode=${request.needExitNode}`, this.logTarget)
    Logger.debug('当前IP:' + request.ip, this.logTarget)
    Logger.info(`setup_tun routes kernel=${JSON.stringify(request.routes ?? [])}`, this.logTarget)
    const vpnConfig = buildTunVpnConfig({
      ip: request.ip,
      mask: request.mask,
      magicDNS: request.magicDNS,
      needExitNode: request.needExitNode,
      routeStrings: request.routes,
      enabled: shouldBuildPreferenceVpnRoutes(request.vpnRoutes),
      whiteList: request.whiteList,
      blackList: request.blackList,
      dev: request.dev,
      dnsAddress: request.dns
    }).vpnConfig
    Logger.info(`setup_tun finalVpnRoutes=${JSON.stringify(vpnConfig.routes ?? [])}`, this.logTarget)
    if (this.vpnConnection === undefined) {
      Logger.error('vpnConnection not found', this.logTarget)
      return
    }
    await this.vpnConnection.destroy()
    Logger.debug('VPN配置:' + JSON.stringify(vpnConfig), this.logTarget)
    this.vpnConnection.create(vpnConfig).then((fd) => {
      Logger.info(`vpnConnection.create success instance=${request.instanceId} fd=${fd}`, this.logTarget)
      this.activateMissionContinue()
      this.setTunFd(request.instanceId, fd)
    }).catch((error: BusinessError) => {
      Logger.error(`vpnConnection create failed: ${error.code}, ${error.message}`, this.logTarget)
    })
  }

  async destroyVpnConnection(): Promise<void> {
    if (!this.vpnConnection) {
      return
    }
    try {
      await this.vpnConnection.destroy()
      Logger.info('vpnConnection destroyed', this.logTarget)
    } catch (error) {
      const err = error as BusinessError
      Logger.error(`vpnConnection destroy failed: ${err.code}, ${err.message}`, this.logTarget)
    } finally {
      this.vpnConnection = undefined
    }
  }

  hasConnection(): boolean {
    return this.vpnConnection !== undefined
  }
}
