import { JSON } from '@kit.ArkTS'
import { deviceInfo } from '@kit.BasicServicesKit'
import { vpnExtension } from '@kit.NetworkKit'
import { isIpAddr } from '../../class/config/IP'
import { ConfigJson } from '../../config/schema/SchemaConfig'
import { TunRequestPayload } from '../../infrastructure/bridge/kernel/KernelBridgeTypes'
import { normalizeRouteStrings, routeSignature } from '../../infrastructure/bridge/kernel/RouteStore'
import { Logger } from '../../shared/logging/Logger'
import { buildTunVpnConfig } from './TunConfigBuilder'
import { TunSetupRequest, TunSetupScheduler } from './TunSetupScheduler'

const TUN_REQUEST_DEBOUNCE_MS = 500
const TUN_RETRY_LIMIT = 3
const TUN_RETRY_BASE_MS = 1000
const TUN_SETUP_BARRIER_TIMEOUT_MS = 10000

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
  setTunFd: (instanceId: string, fd: number) => boolean
}

export class VpnExtensionTunService {
  private readonly context: vpnExtension.VpnExtensionContext
  private readonly logTarget: Object | string
  private readonly instanceId: string
  private readonly config: ConfigJson | undefined
  private readonly settings: VpnExtensionTunSettings
  private readonly publishContinuationState: (active: boolean) => void
  private readonly setTunFd: (instanceId: string, fd: number) => boolean
  private vpnConnection: vpnExtension.VpnConnection | undefined = undefined
  private currentTunFd: number = -1
  private tunCreateSeq: number = 0
  private currentTunSignature: string = ''
  private currentRoutesSignature: string = ''
  private tunSetupInFlight: boolean = false
  private lastRoutesSignature: string = ''
  private needTUN: boolean = false
  private tunSetupScheduler: TunSetupScheduler
  private failedRequest: TunSetupRequest | undefined = undefined
  private retryTimer: number = -1
  private retryCount: number = 0
  private retryExhaustedSignature: string = ''
  private lastSuccessfulRequest: TunSetupRequest | undefined = undefined
  private generation: number = 0
  private kernelRestartRequested: boolean = false
  private kernelRestartActive: boolean = false
  private restartPendingRequest: TunSetupRequest | undefined = undefined
  private setupIdleWaiters: Array<() => void> = []
  private destroying: boolean = false

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
    if (this.destroying) {
      return
    }
    Logger.info(`kernel tun_request trigger instance=${this.instanceId} cidr=${payload.virtualIpv4Cidr ?? ''} sig=${routeSignature(payload.aggregatedRoutes ?? [])}`, this.logTarget)
    this.needTUN = false
    const cidr = payload.virtualIpv4Cidr ?? ''
    const ip = payload.virtualIpv4 ?? cidr.split('/')[0]
    const mask = Number(cidr.split('/')[1] ?? '24')
    const routes = normalizeRouteStrings(payload.aggregatedRoutes ?? [])
    const signature = this.buildTunSignature(ip, mask, payload.magicDnsEnabled, payload.needExitNode, routes)
    const nextRoutesSignature = routeSignature(routes)
    const request: TunSetupRequest = {
      ip,
      mask,
      magicDNS: payload.magicDnsEnabled,
      needExitNode: payload.needExitNode,
      routes,
      signature,
      trigger
    }
    if (this.kernelRestartRequested || this.kernelRestartActive) {
      this.restartPendingRequest = request
      const attached = this.attachCurrentTun()
      Logger.info(`deferred vpn route transaction during kernel restart fd=${this.currentTunFd} attached=${attached} routeChanged=${nextRoutesSignature !== this.currentRoutesSignature} trigger=${trigger}`, this.logTarget)
      return
    }
    if (this.currentTunFd > 0 && signature === this.currentTunSignature) {
      this.tunSetupScheduler.clear()
      if (this.setTunFd(this.instanceId, this.currentTunFd)) {
        this.publishContinuationState(true)
        Logger.info(`reused existing TUN fd=${this.currentTunFd}; VPN config unchanged trigger=${trigger}`, this.logTarget)
      } else {
        Logger.error(`setTunFd rejected while reusing existing TUN instance=${this.instanceId}`, this.logTarget)
      }
      return
    }
    if (this.retryExhaustedSignature === signature) {
      Logger.debug(`ignore exhausted duplicate TUN request sig=${signature}`, this.logTarget)
      return
    }
    if (this.failedRequest?.signature === signature && this.retryTimer >= 0) {
      Logger.debug(`coalesce duplicate TUN request during retry sig=${signature}`, this.logTarget)
      return
    }
    if (this.failedRequest && this.failedRequest.signature !== signature) {
      this.failedRequest = undefined
      this.retryCount = 0
      this.retryExhaustedSignature = ''
      if (this.retryTimer >= 0) {
        clearTimeout(this.retryTimer)
        this.retryTimer = -1
      }
    }
    this.lastRoutesSignature = routeSignature(routes)
    Logger.debug(`setupTunFromPayload instance=${this.instanceId} trigger=${trigger} sig=${signature} routeSig=${this.lastRoutesSignature} cidr=${cidr} ip=${ip} routes=${JSON.stringify(routes)}`, this.logTarget)
    this.tunSetupScheduler.schedule(request)
  }

  async destroy(): Promise<void> {
    this.destroying = true
    this.generation++
    this.tunSetupScheduler.clear()
    this.failedRequest = undefined
    this.retryCount = 0
    this.retryExhaustedSignature = ''
    this.lastSuccessfulRequest = undefined
    this.currentTunFd = -1
    this.currentTunSignature = ''
    this.currentRoutesSignature = ''
    this.kernelRestartRequested = false
    this.kernelRestartActive = false
    this.restartPendingRequest = undefined
    if (this.retryTimer >= 0) {
      clearTimeout(this.retryTimer)
      this.retryTimer = -1
    }
    await this.waitForSetupCompletion()
    const vpnConnection = this.vpnConnection
    this.vpnConnection = undefined
    if (vpnConnection) {
      try {
        await vpnConnection.destroy()
      } catch (error) {
        const err = error as Error
        Logger.debug(`vpnConnection destroy failed during shutdown: ${err.message}`, this.logTarget)
      }
    }
    this.resolveSetupIdleWaiters()
  }

  async beginKernelRestart(): Promise<boolean> {
    if (this.destroying || this.kernelRestartRequested || this.kernelRestartActive) {
      return false
    }
    this.kernelRestartRequested = true
    this.restartPendingRequest = this.tunSetupScheduler.takePending()
    this.failedRequest = undefined
    this.retryCount = 0
    this.retryExhaustedSignature = ''
    if (this.retryTimer >= 0) {
      clearTimeout(this.retryTimer)
      this.retryTimer = -1
    }
    const setupIdle = await this.waitForSetupIdle()
    if (!setupIdle) {
      this.kernelRestartRequested = false
      const pendingRequest = this.restartPendingRequest
      this.restartPendingRequest = undefined
      Logger.error('kernel restart cancelled because vpn route transaction did not become idle', this.logTarget)
      if (pendingRequest) {
        this.tunSetupScheduler.schedule(pendingRequest)
      }
      return false
    }
    this.kernelRestartRequested = false
    this.kernelRestartActive = true
    Logger.info(`kernel restart transaction began fd=${this.currentTunFd} routeSig=${this.currentRoutesSignature}`, this.logTarget)
    return true
  }

  async completeKernelRestart(started: boolean): Promise<void> {
    if (!this.kernelRestartRequested && !this.kernelRestartActive) {
      return
    }
    const pendingRequest = this.restartPendingRequest
    this.kernelRestartRequested = false
    this.kernelRestartActive = false
    this.restartPendingRequest = undefined
    Logger.info(`kernel restart transaction completed started=${started} pendingTun=${pendingRequest !== undefined}`, this.logTarget)
    if (!started || this.destroying) {
      return
    }
    if (!pendingRequest) {
      const attached = this.attachCurrentTun()
      Logger.info(`kernel restart reattached existing TUN without a new request fd=${this.currentTunFd} attached=${attached}`, this.logTarget)
      return
    }
    const nextRoutesSignature = routeSignature(pendingRequest.routes)
    if (this.currentTunFd > 0 && nextRoutesSignature === this.currentRoutesSignature) {
      const attached = this.attachCurrentTun()
      Logger.info(`kernel restart reused TUN fd=${this.currentTunFd} attached=${attached} route table unchanged`, this.logTarget)
      return
    }
    Logger.info(`kernel restart queued stable VPN config routeChanged=${nextRoutesSignature !== this.currentRoutesSignature} old=${this.currentRoutesSignature} new=${nextRoutesSignature}`, this.logTarget)
    this.tunSetupScheduler.schedule(pendingRequest)
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
    if (this.destroying) {
      return
    }
    if (this.kernelRestartRequested || this.kernelRestartActive) {
      this.restartPendingRequest = request
      const attached = this.attachCurrentTun()
      Logger.info(`deferred queued vpn route transaction during kernel restart fd=${this.currentTunFd} attached=${attached}`, this.logTarget)
      return
    }
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
      dnsAddress: isIpAddr(this.settings.dns) ? this.settings.dns : '223.5.5.5'
    })
    Logger.debug(`setupTunWithRoutes parsedRoutes=${JSON.stringify(tunConfig.parsedRoutes.map((route) => route.networkAddress + '/' + route.prefix))}`, this.logTarget)

    const vpnConfig = tunConfig.vpnConfig
    Logger.debug(`setupTunWithRoutes finalVpnRoutes=${JSON.stringify(vpnConfig.routes ?? [])}`, this.logTarget)

    if (!this.vpnConnection) {
      this.vpnConnection = vpnExtension.createVpnConnection(this.context)
      Logger.debug('vpnConnection created in EasyTierAbility', this.logTarget)
    }
    const vpnConnection = this.vpnConnection
    const generation = this.generation
    Logger.debug('VpnConfig: ' + JSON.stringify(vpnConfig, undefined, 2), this.logTarget)

    Logger.info(`setupTunWithRoutes calling create seq=${this.tunCreateSeq} trigger=${request.trigger}`, this.logTarget)
    try {
      await vpnConnection.destroy()
      if (generation !== this.generation) {
        return
      }
      this.currentTunSignature = ''
      this.currentTunFd = -1
      this.currentRoutesSignature = ''
      const fd = await vpnConnection.create(vpnConfig)
      if (generation !== this.generation) {
        await vpnConnection.destroy()
        return
      }
      Logger.info(`vpnConnection.create success instance=${this.instanceId} fd=${fd} seq=${this.tunCreateSeq} trigger=${request.trigger}`, this.logTarget)
      if (!this.setTunFd(this.instanceId, fd)) {
        throw new Error(`setTunFd rejected instance=${this.instanceId}`)
      }
      this.currentTunSignature = request.signature
      this.currentTunFd = fd
      this.currentRoutesSignature = routeSignature(request.routes)
      this.failedRequest = undefined
      this.retryCount = 0
      this.retryExhaustedSignature = ''
      this.lastSuccessfulRequest = request
      this.publishContinuationState(true)
      Logger.debug(`setTunFd sent instance=${this.instanceId}`, this.logTarget)
    } catch (err) {
      if (generation !== this.generation) {
        return
      }
      this.currentTunSignature = ''
      this.currentTunFd = -1
      this.currentRoutesSignature = ''
      this.publishContinuationState(false)
      Logger.error(`vpnConnection create failed: ${JSON.stringify(err)}`, this.logTarget)
      this.scheduleRetry(request)
    } finally {
      this.tunSetupInFlight = false
      this.resolveSetupIdleWaiters()
      this.tunSetupScheduler.flush()
    }
  }

  private scheduleRetry(request: TunSetupRequest): void {
    if (this.destroying || this.kernelRestartRequested || this.kernelRestartActive) {
      this.restartPendingRequest = request
      return
    }
    if (this.failedRequest && this.failedRequest.signature === request.signature && this.retryTimer >= 0) {
      return
    }
    this.failedRequest = request
    this.retryCount++
    if (this.retryCount > TUN_RETRY_LIMIT) {
      Logger.error(`TUN retry limit reached sig=${request.signature}`, this.logTarget)
      this.retryExhaustedSignature = request.signature
      const rollbackRequest = this.lastSuccessfulRequest
      if (rollbackRequest && rollbackRequest.signature !== request.signature) {
        Logger.warn(`TUN setup exhausted; restoring last successful config sig=${rollbackRequest.signature}`, this.logTarget)
        this.failedRequest = undefined
        this.retryCount = 0
        this.retryExhaustedSignature = ''
        this.tunSetupScheduler.schedule({
          ip: rollbackRequest.ip,
          mask: rollbackRequest.mask,
          magicDNS: rollbackRequest.magicDNS,
          needExitNode: rollbackRequest.needExitNode,
          routes: rollbackRequest.routes,
          signature: rollbackRequest.signature,
          trigger: 'rollback_last_known_good'
        })
      }
      return
    }
    const delayMs = TUN_RETRY_BASE_MS * this.retryCount
    Logger.info(`TUN retry=${this.retryCount} delayMs=${delayMs}`, this.logTarget)
    this.retryTimer = setTimeout(() => {
      this.retryTimer = -1
      if (this.failedRequest?.signature === request.signature) {
        this.tunSetupScheduler.schedule(request)
      }
    }, delayMs)
  }

  private attachCurrentTun(): boolean {
    if (this.currentTunFd <= 0) {
      return false
    }
    const attached = this.setTunFd(this.instanceId, this.currentTunFd)
    if (attached) {
      this.publishContinuationState(true)
    }
    return attached
  }

  private waitForSetupIdle(): Promise<boolean> {
    if (!this.tunSetupInFlight) {
      return Promise.resolve(true)
    }
    return new Promise<boolean>((resolve) => {
      let completed = false
      const finish = (idle: boolean): void => {
        if (completed) {
          return
        }
        completed = true
        resolve(idle)
      }
      const timeoutId = setTimeout(() => {
        finish(false)
      }, TUN_SETUP_BARRIER_TIMEOUT_MS)
      this.setupIdleWaiters.push(() => {
        clearTimeout(timeoutId)
        finish(true)
      })
    })
  }

  private waitForSetupCompletion(): Promise<void> {
    if (!this.tunSetupInFlight) {
      return Promise.resolve()
    }
    return new Promise<void>((resolve) => {
      this.setupIdleWaiters.push(resolve)
    })
  }

  private resolveSetupIdleWaiters(): void {
    if (this.tunSetupInFlight || this.setupIdleWaiters.length === 0) {
      return
    }
    const waiters = this.setupIdleWaiters
    this.setupIdleWaiters = []
    waiters.forEach((resolve) => {
      resolve()
    })
  }
}
