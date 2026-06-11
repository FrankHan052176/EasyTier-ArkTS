import { JSON } from '@kit.ArkTS'
import { deviceInfo } from '@kit.BasicServicesKit'
import { vpnExtension } from '@kit.NetworkKit'
import { ConfigJson } from '../../config/schema/SchemaConfig'
import { TunRequestPayload } from '../../infrastructure/bridge/kernel/KernelBridgeTypes'
import { normalizeRouteStrings, routeSignature } from '../../infrastructure/bridge/kernel/RouteStore'
import { Logger } from '../../shared/logging/Logger'
import { buildTunVpnConfig } from './TunConfigBuilder'
import { TunSetupRequest, TunSetupScheduler } from './TunSetupScheduler'

const TUN_REQUEST_DEBOUNCE_MS = 500

export interface VpnExtensionTunSettings {
  whiteList: boolean
  blackList: string[]
  dns: string
  dev: boolean
  forceGlobal: boolean
}

export interface VpnExtensionTunServiceOptions {
  context: vpnExtension.VpnExtensionContext
  logTarget: Object | string
  instanceId: string
  config: ConfigJson | undefined
  settings: VpnExtensionTunSettings
  publishContinuationState: (active: boolean) => void
  setTunFd: (instanceId: string, fd: number) => void
}

export class VpnExtensionTunService {
  private readonly context: vpnExtension.VpnExtensionContext
  private readonly logTarget: Object | string
  private readonly instanceId: string
  private readonly config: ConfigJson | undefined
  private readonly settings: VpnExtensionTunSettings
  private readonly publishContinuationState: (active: boolean) => void
  private readonly setTunFd: (instanceId: string, fd: number) => void
  private vpnConnection: vpnExtension.VpnConnection | undefined = undefined
  private tunCreateSeq: number = 0
  private currentTunSignature: string = ''
  private tunSetupInFlight: boolean = false
  private lastRoutesSignature: string = ''
  private needTUN: boolean = false
  private tunSetupScheduler: TunSetupScheduler

  constructor(options: VpnExtensionTunServiceOptions) {
    this.context = options.context
    this.logTarget = options.logTarget
    this.instanceId = options.instanceId
    this.config = options.config
    this.settings = options.settings
    this.publishContinuationState = options.publishContinuationState
    this.setTunFd = options.setTunFd
    this.needTUN = !(options.config?.no_tun ?? false)
    this.tunSetupScheduler = new TunSetupScheduler({
      debounceMs: TUN_REQUEST_DEBOUNCE_MS,
      getCurrentSignature: () => this.currentTunSignature,
      getInFlight: () => this.tunSetupInFlight,
      onSchedule: (request: TunSetupRequest) => {
        this.setupTunWithRoutes(request).catch((err: Error) => {
          Logger.error(`setupTunWithRoutes failed: ${JSON.stringify(err)}`, this.logTarget)
        })
      },
      onClearTimer: (timerId: number) => {
        clearTimeout(timerId)
      },
      onLog: (message: string) => {
        Logger.debug(message, this.logTarget)
      }
    })
  }

  async prepareProtection(): Promise<void> {
    if (!this.shouldProtectProcessNet()) {
      return
    }
    if (!this.vpnConnection) {
      this.vpnConnection = vpnExtension.createVpnConnection(this.context)
      Logger.debug('vpnConnection created for process protection', this.logTarget)
    }
    await this.vpnConnection.protectProcessNet()
    Logger.info('protectProcessNet completed before kernel start', this.logTarget)
  }

  handleKernelTunRequest(payload: TunRequestPayload, trigger: string): void {
    Logger.info(`kernel tun_request trigger instance=${this.instanceId} cidr=${payload.virtualIpv4Cidr ?? ''} sig=${routeSignature(payload.aggregatedRoutes ?? [])}`, this.logTarget)
    this.needTUN = false
    const cidr = payload.virtualIpv4Cidr ?? ''
    const ip = payload.virtualIpv4 ?? cidr.split('/')[0]
    const mask = Number(cidr.split('/')[1] ?? '24')
    const routes = normalizeRouteStrings(payload.aggregatedRoutes ?? [])
    const signature = this.buildTunSignature(ip, mask, payload.magicDnsEnabled, payload.needExitNode, routes)
    this.lastRoutesSignature = routeSignature(routes)
    Logger.debug(`setupTunFromPayload instance=${this.instanceId} trigger=${trigger} sig=${signature} routeSig=${this.lastRoutesSignature} cidr=${cidr} ip=${ip} routes=${JSON.stringify(routes)}`, this.logTarget)
    this.tunSetupScheduler.schedule({
      ip,
      mask,
      magicDNS: payload.magicDnsEnabled,
      needExitNode: payload.needExitNode,
      routes,
      signature,
      trigger
    })
  }

  destroy(): void {
    this.tunSetupScheduler.clear()
    this.vpnConnection?.destroy()
  }

  private shouldProtectProcessNet(): boolean {
    return deviceInfo.sdkApiVersion >= 22 && this.settings.forceGlobal && (this.config?.exit_nodes?.length ?? 0) > 0
  }

  private buildTunSignature(ip: string, mask: number, magicDNS: boolean, needExitNode: boolean, routes: string[]): string {
    return JSON.stringify({
      ip,
      mask,
      magicDNS,
      needExitNode,
      forceGlobal: this.settings.forceGlobal,
      whiteList: this.settings.whiteList,
      blackList: [...this.settings.blackList].sort(),
      dns: this.settings.dns,
      dev: this.settings.dev,
      routes: normalizeRouteStrings(routes)
    })
  }

  private async setupTunWithRoutes(request: TunSetupRequest): Promise<void> {
    this.tunCreateSeq++
    this.tunSetupInFlight = true
    Logger.info(`Setting up TUN #${this.tunCreateSeq} for ${request.ip}/${request.mask} trigger=${request.trigger} sig=${request.signature}`, this.logTarget)
    Logger.debug(`setupTunWithRoutes routes kernel=${JSON.stringify(request.routes)}`, this.logTarget)
    const tunConfig = buildTunVpnConfig({
      ip: request.ip,
      mask: request.mask,
      magicDNS: request.magicDNS,
      needExitNode: request.needExitNode,
      routeStrings: request.routes,
      enabled: true,
      forceGlobal: this.settings.forceGlobal,
      ignoreInvalidRoutes: true,
      whiteList: this.settings.whiteList,
      blackList: this.settings.blackList,
      dev: this.settings.dev,
      dnsAddress: this.settings.dns
    })
    Logger.debug(`setupTunWithRoutes parsedRoutes=${JSON.stringify(tunConfig.parsedRoutes.map((route) => route.networkAddress + '/' + route.prefix))}`, this.logTarget)

    const vpnConfig = tunConfig.vpnConfig
    Logger.debug(`setupTunWithRoutes finalVpnRoutes=${JSON.stringify(vpnConfig.routes ?? [])}`, this.logTarget)

    if (!this.vpnConnection) {
      this.vpnConnection = vpnExtension.createVpnConnection(this.context)
      Logger.debug('vpnConnection created in EasyTierAbility', this.logTarget)
    }
    Logger.debug('VpnConfig: ' + JSON.stringify(vpnConfig, undefined, 2), this.logTarget)

    Logger.info(`setupTunWithRoutes calling create seq=${this.tunCreateSeq} trigger=${request.trigger}`, this.logTarget)
    try {
      await this.vpnConnection.destroy()
      const fd = await this.vpnConnection.create(vpnConfig)
      this.currentTunSignature = request.signature
      Logger.info(`vpnConnection.create success instance=${this.instanceId} fd=${fd} seq=${this.tunCreateSeq} trigger=${request.trigger}`, this.logTarget)
      this.publishContinuationState(true)
      this.setTunFd(this.instanceId, fd)
      Logger.debug(`setTunFd sent instance=${this.instanceId}`, this.logTarget)
    } catch (err) {
      this.publishContinuationState(false)
      Logger.error(`vpnConnection create failed: ${JSON.stringify(err)}`, this.logTarget)
    } finally {
      this.tunSetupInFlight = false
      this.tunSetupScheduler.flush()
    }
  }
}
