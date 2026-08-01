import { common } from '@kit.AbilityKit'
import { BusinessError } from '@kit.BasicServicesKit'
import { vpnExtension } from '@kit.NetworkKit'
import { normalizeRouteStrings, routeSignature } from '../../infrastructure/bridge/kernel/RouteStore'
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
  requestVpnPerm: (callback: () => void, errorCallback?: (error: BusinessError) => void) => void
  activateMissionContinue: () => void
  setTunFd: (instanceId: string, fd: number) => boolean
}

/**
 * Entry 进程内唯一的 VPN/TUN 生命周期所有者。
 *
 * 内核可以在启动和切网重连阶段连续上报多份路由快照。已有 TUN 时只消费
 * 500ms 稳定窗口内的最后一份配置；初次创建仍立即执行。所有 create/destroy
 * 都经过同一事务队列，禁止旧销毁与下一次启动交叉。
 */
export class EntryVpnConnectionService {
  private static readonly TUN_STABILITY_MS: number = 500
  private static readonly TUN_RETRY_LIMIT: number = 3
  private static readonly TUN_RETRY_BASE_MS: number = 1000
  private static readonly SETUP_BARRIER_TIMEOUT_MS: number = 10000
  private readonly context: common.UIAbilityContext
  private readonly logTarget: Object | string
  private readonly requestVpnPerm: (callback: () => void, errorCallback?: (error: BusinessError) => void) => void
  private readonly activateMissionContinue: () => void
  private readonly setTunFd: (instanceId: string, fd: number) => boolean
  private vpnConnection: vpnExtension.VpnConnection | undefined = undefined
  private currentTunFd: number = -1
  private currentTunSignature: string = ''
  private currentRoutesSignature: string = ''
  private pendingSetup: EntryVpnSetupRequest | undefined = undefined
  private stableSetupTimer: number = -1
  private setupInFlight: boolean = false
  private retryTimer: number = -1
  private retryCount: number = 0
  private retrySignature: string = ''
  private retryExhaustedSignature: string = ''
  private inFlightSignature: string = ''
  private inFlightGeneration: number = -1
  private lastSuccessfulRequest: EntryVpnSetupRequest | undefined = undefined
  private generation: number = 0
  private kernelRestartRequested: boolean = false
  private kernelRestartActive: boolean = false
  private restartPendingSetup: EntryVpnSetupRequest | undefined = undefined
  private setupIdleWaiters: Array<() => void> = []
  private destroying: boolean = false
  private destroyPromise: Promise<void> | undefined = undefined

  constructor(options: EntryVpnConnectionServiceOptions) {
    this.context = options.context
    this.logTarget = options.logTarget
    this.requestVpnPerm = options.requestVpnPerm
    this.activateMissionContinue = options.activateMissionContinue
    this.setTunFd = options.setTunFd
  }

  prepareVpn(shouldProtect: boolean = false, callback: () => void = () => {}): void {
    this.prepareVpnAsync(shouldProtect).then(callback).catch((error: Error) => {
      Logger.error(`prepare vpn failed: ${error.message}`, this.logTarget)
    })
  }

  async prepareVpnAsync(shouldProtect: boolean = false): Promise<void> {
    const destroying = this.destroyPromise
    if (destroying) {
      await destroying
    }
    if (this.vpnConnection !== undefined) {
      Logger.info('prepare_vpn reuse existing vpnConnection', this.logTarget)
      if (shouldProtect) {
        await this.vpnConnection.protectProcessNet()
        Logger.info('protectProcessNet completed before kernel start', this.logTarget)
      }
      return
    }
    Logger.info('prepare vpn', this.logTarget)
    await new Promise<void>((resolve, reject) => {
      this.requestVpnPerm(async () => {
        try {
          this.vpnConnection = vpnExtension.createVpnConnection(this.context as Object as vpnExtension.VpnExtensionContext)
          Logger.info('vpnConnection created in prepare_vpn', this.logTarget)
          if (shouldProtect) {
            await this.vpnConnection?.protectProcessNet()
            Logger.info('protectProcessNet completed before kernel start', this.logTarget)
          }
          resolve()
        } catch (error) {
          reject(error)
        }
      }, (error: BusinessError) => {
        reject(error)
      })
    })
  }

  async setupTun(request: EntryVpnSetupRequest): Promise<void> {
    if (this.destroying) {
      Logger.debug(`ignore TUN setup while destroying instance=${request.instanceId}`, this.logTarget)
      return
    }
    request.routes = normalizeRouteStrings(request.routes ?? [])
    const signature = this.buildRequestSignature(request)
    const nextRoutesSignature = routeSignature(request.routes)
    if (this.kernelRestartRequested || this.kernelRestartActive) {
      this.restartPendingSetup = request
      const attached = this.attachCurrentTun(request.instanceId)
      Logger.info(`deferred vpn config during kernel restart fd=${this.currentTunFd} attached=${attached} routeChanged=${nextRoutesSignature !== this.currentRoutesSignature} instance=${request.instanceId}`, this.logTarget)
      return
    }
    if (this.currentTunFd > 0 && signature === this.currentTunSignature) {
      this.cancelPendingSetup()
      const attached = this.attachCurrentTun(request.instanceId)
      Logger.info(`reused existing TUN fd=${this.currentTunFd}; VPN config unchanged attached=${attached} instance=${request.instanceId}`, this.logTarget)
      return
    }
    if (this.retryExhaustedSignature === signature) {
      Logger.debug(`ignore exhausted duplicate vpn setup instance=${request.instanceId}`, this.logTarget)
      return
    }
    if ((this.retryTimer >= 0 && this.retrySignature === signature) ||
      (this.setupInFlight && this.inFlightGeneration === this.generation && this.inFlightSignature === signature && !this.pendingSetup)) {
      Logger.debug(`coalesce duplicate vpn setup instance=${request.instanceId}`, this.logTarget)
      return
    }
    if (this.retrySignature.length > 0 && this.retrySignature !== signature) {
      this.clearRetryState()
    }
    this.pendingSetup = request
    if (this.currentTunFd <= 0 && !this.setupInFlight) {
      this.clearStableSetupTimer()
      await this.drainSetupQueue()
      return
    }
    this.clearStableSetupTimer()
    this.stableSetupTimer = setTimeout(() => {
      this.stableSetupTimer = -1
      void this.drainSetupQueue()
    }, EntryVpnConnectionService.TUN_STABILITY_MS)
    Logger.info(`queued stable VPN config instance=${request.instanceId} routeChanged=${nextRoutesSignature !== this.currentRoutesSignature} sig=${signature}`, this.logTarget)
  }

  private async drainSetupQueue(): Promise<void> {
    if (this.destroying || this.setupInFlight || this.stableSetupTimer >= 0 || !this.pendingSetup) {
      return
    }
    const request = this.pendingSetup
    this.pendingSetup = undefined
    const signature = this.buildRequestSignature(request)
    if (this.currentTunFd > 0 && signature === this.currentTunSignature) {
      const attached = this.attachCurrentTun(request.instanceId)
      Logger.info(`dropped restored VPN config before rebuild fd=${this.currentTunFd} attached=${attached}`, this.logTarget)
      return
    }
    this.setupInFlight = true
    this.inFlightSignature = signature
    this.inFlightGeneration = this.generation
    try {
      const setupApplied = await this.performSetupTun(request)
      if (setupApplied) {
        this.clearRetryState()
        this.lastSuccessfulRequest = request
      }
    } catch (error) {
      const err = error as BusinessError
      Logger.error(`vpnConnection create failed: ${err.code ?? 0}, ${err.message}`, this.logTarget)
      if (!this.pendingSetup) {
        this.scheduleTunRetry(request)
      }
    } finally {
      this.setupInFlight = false
      this.inFlightSignature = ''
      this.inFlightGeneration = -1
      this.resolveSetupIdleWaiters()
      if (this.pendingSetup && this.stableSetupTimer < 0 && this.retryTimer < 0 && !this.destroying) {
        await this.drainSetupQueue()
      }
    }
  }

  private async performSetupTun(request: EntryVpnSetupRequest): Promise<boolean> {
    if (this.destroying) {
      return false
    }
    if (this.kernelRestartRequested || this.kernelRestartActive) {
      this.restartPendingSetup = request
      const attached = this.attachCurrentTun(request.instanceId)
      Logger.info(`deferred queued vpn config during kernel restart fd=${this.currentTunFd} attached=${attached} instance=${request.instanceId}`, this.logTarget)
      return false
    }
    const signature = this.buildRequestSignature(request)
    if (this.currentTunFd > 0 && signature === this.currentTunSignature) {
      return this.attachCurrentTun(request.instanceId)
    }
    Logger.info(`setup_tun start instance=${request.instanceId} ip=${request.ip}/${request.mask} magicDNS=${request.magicDNS} needExitNode=${request.needExitNode}`, this.logTarget)
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
    const vpnConnection = this.vpnConnection
    if (vpnConnection === undefined) {
      throw new Error('vpnConnection not found')
    }
    const generation = this.generation
    if (this.currentTunFd > 0) {
      await vpnConnection.destroy()
      this.currentTunFd = -1
      this.currentTunSignature = ''
      this.currentRoutesSignature = ''
      if (generation !== this.generation || this.destroying) {
        return false
      }
    }
    Logger.debug('VPN配置:' + JSON.stringify(vpnConfig), this.logTarget)
    const fd = await vpnConnection.create(vpnConfig)
    if (generation !== this.generation || this.destroying) {
      await vpnConnection.destroy()
      return false
    }
    Logger.info(`vpnConnection.create success instance=${request.instanceId} fd=${fd}`, this.logTarget)
    if (!this.setTunFd(request.instanceId, fd)) {
      await vpnConnection.destroy()
      throw new Error(`setTunFd rejected instance=${request.instanceId}`)
    }
    this.currentTunFd = fd
    this.currentTunSignature = signature
    this.currentRoutesSignature = routeSignature(request.routes ?? [])
    this.activateMissionContinue()
    return true
  }

  private buildRequestSignature(request: EntryVpnSetupRequest): string {
    return JSON.stringify({
      ip: request.ip,
      mask: request.mask,
      magicDNS: request.magicDNS,
      instanceId: request.instanceId,
      needExitNode: request.needExitNode,
      routes: normalizeRouteStrings(request.routes ?? []),
      vpnRoutes: request.vpnRoutes,
      whiteList: request.whiteList,
      blackList: [...request.blackList].sort(),
      dev: request.dev,
      dns: request.dns
    })
  }

  private scheduleTunRetry(request: EntryVpnSetupRequest): void {
    if (this.destroying || this.kernelRestartRequested || this.kernelRestartActive) {
      this.restartPendingSetup = request
      return
    }
    const signature = this.buildRequestSignature(request)
    if (this.retrySignature !== signature) {
      this.retrySignature = signature
      this.retryCount = 0
    }
    this.retryCount++
    if (this.retryCount > EntryVpnConnectionService.TUN_RETRY_LIMIT) {
      Logger.error(`vpnConnection retry limit reached instance=${request.instanceId}`, this.logTarget)
      this.retryExhaustedSignature = signature
      const rollbackRequest = this.lastSuccessfulRequest
      if (rollbackRequest && this.buildRequestSignature(rollbackRequest) !== signature) {
        Logger.warn(`vpn setup exhausted; restoring last successful config instance=${rollbackRequest.instanceId}`, this.logTarget)
        this.clearRetryState()
        this.pendingSetup = rollbackRequest
        this.clearStableSetupTimer()
        void this.drainSetupQueue()
      }
      return
    }
    const delayMs = EntryVpnConnectionService.TUN_RETRY_BASE_MS * this.retryCount
    this.pendingSetup = request
    Logger.info(`vpnConnection retry=${this.retryCount} delayMs=${delayMs}`, this.logTarget)
    this.retryTimer = setTimeout(() => {
      this.retryTimer = -1
      void this.drainSetupQueue()
    }, delayMs)
  }

  async destroyVpnConnection(): Promise<void> {
    const existingDestroy = this.destroyPromise
    if (existingDestroy) {
      return await existingDestroy
    }
    this.destroying = true
    this.generation++
    this.cancelPendingSetup()
    this.clearRetryState()
    this.kernelRestartRequested = false
    this.kernelRestartActive = false
    this.restartPendingSetup = undefined
    const destroyPromise = this.finishDestroyVpnConnection()
    this.destroyPromise = destroyPromise
    return destroyPromise.then(() => {
      if (this.destroyPromise === destroyPromise) {
        this.destroyPromise = undefined
      }
      this.destroying = false
    }, (error: Error) => {
      if (this.destroyPromise === destroyPromise) {
        this.destroyPromise = undefined
      }
      this.destroying = false
      throw error
    })
  }

  private async finishDestroyVpnConnection(): Promise<void> {
    await this.waitForSetupCompletion()
    this.cancelPendingSetup()
    this.clearRetryState()
    this.kernelRestartRequested = false
    this.kernelRestartActive = false
    this.restartPendingSetup = undefined
    const vpnConnection = this.vpnConnection
    this.vpnConnection = undefined
    this.currentTunFd = -1
    this.currentTunSignature = ''
    this.currentRoutesSignature = ''
    this.lastSuccessfulRequest = undefined
    if (!vpnConnection) {
      return
    }
    try {
      await vpnConnection.destroy()
      Logger.info('vpnConnection destroyed', this.logTarget)
    } catch (error) {
      const err = error as BusinessError
      Logger.error(`vpnConnection destroy failed: ${err.code ?? 0}, ${err.message}`, this.logTarget)
      throw new Error(`vpnConnection destroy failed: ${err.code ?? 0}, ${err.message}`)
    }
  }

  async beginKernelRestart(): Promise<boolean> {
    if (this.destroying || this.kernelRestartRequested || this.kernelRestartActive) {
      return false
    }
    this.kernelRestartRequested = true
    this.restartPendingSetup = this.pendingSetup
    this.pendingSetup = undefined
    this.clearStableSetupTimer()
    this.clearRetryState()
    const setupIdle = await this.waitForSetupIdle()
    if (!setupIdle) {
      this.kernelRestartRequested = false
      const pendingRequest = this.restartPendingSetup
      this.restartPendingSetup = undefined
      Logger.error('kernel restart cancelled because vpn config transaction did not become idle', this.logTarget)
      if (pendingRequest) {
        await this.setupTun(pendingRequest)
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
    const pendingRequest = this.restartPendingSetup
    this.kernelRestartRequested = false
    this.kernelRestartActive = false
    this.restartPendingSetup = undefined
    Logger.info(`kernel restart transaction completed started=${started} pendingTun=${pendingRequest !== undefined}`, this.logTarget)
    if (!started || this.destroying) {
      return
    }
    if (!pendingRequest) {
      const lastRequest = this.lastSuccessfulRequest
      if (lastRequest && this.currentTunFd > 0) {
        const attached = this.attachCurrentTun(lastRequest.instanceId)
        Logger.info(`kernel restart reattached existing TUN without a new request fd=${this.currentTunFd} attached=${attached}`, this.logTarget)
      }
      return
    }
    const nextRoutesSignature = routeSignature(pendingRequest.routes ?? [])
    if (this.currentTunFd > 0 && nextRoutesSignature === this.currentRoutesSignature) {
      const attached = this.attachCurrentTun(pendingRequest.instanceId)
      Logger.info(`kernel restart reused TUN fd=${this.currentTunFd} attached=${attached} route table unchanged`, this.logTarget)
      return
    }
    Logger.info(`kernel restart queued stable VPN config routeChanged=${nextRoutesSignature !== this.currentRoutesSignature} old=${this.currentRoutesSignature} new=${nextRoutesSignature}`, this.logTarget)
    await this.setupTun(pendingRequest)
  }

  hasConnection(): boolean {
    return this.vpnConnection !== undefined
  }

  private attachCurrentTun(instanceId: string): boolean {
    if (this.currentTunFd <= 0) {
      return false
    }
    const attached = this.setTunFd(instanceId, this.currentTunFd)
    if (attached) {
      this.activateMissionContinue()
    }
    return attached
  }

  private cancelPendingSetup(): void {
    this.pendingSetup = undefined
    this.clearStableSetupTimer()
  }

  private clearStableSetupTimer(): void {
    if (this.stableSetupTimer >= 0) {
      clearTimeout(this.stableSetupTimer)
      this.stableSetupTimer = -1
    }
  }

  private clearRetryState(): void {
    if (this.retryTimer >= 0) {
      clearTimeout(this.retryTimer)
      this.retryTimer = -1
    }
    this.retryCount = 0
    this.retrySignature = ''
    this.retryExhaustedSignature = ''
  }

  private waitForSetupIdle(): Promise<boolean> {
    if (!this.setupInFlight) {
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
      }, EntryVpnConnectionService.SETUP_BARRIER_TIMEOUT_MS)
      this.setupIdleWaiters.push(() => {
        clearTimeout(timeoutId)
        finish(true)
      })
    })
  }

  private waitForSetupCompletion(): Promise<void> {
    if (!this.setupInFlight) {
      return Promise.resolve()
    }
    return new Promise<void>((resolve) => {
      this.setupIdleWaiters.push(resolve)
    })
  }

  private resolveSetupIdleWaiters(): void {
    if (this.setupInFlight || this.setupIdleWaiters.length === 0) {
      return
    }
    const waiters = this.setupIdleWaiters
    this.setupIdleWaiters = []
    waiters.forEach((resolve) => {
      resolve()
    })
  }
}
