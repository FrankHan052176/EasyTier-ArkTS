import { emitter } from '@kit.BasicServicesKit'
import { isIpAddr } from '../../class/config/IP'
import { TunRequestPayload } from '../../infrastructure/bridge/kernel/KernelBridgeTypes'
import { EntryVpnSetupRequest } from './EntryVpnConnectionService'

const DEFAULT_DNS = '223.5.5.5'

export interface EntryVpnRuntimeSettings {
  vpnRoutes: boolean
  whiteList: boolean
  blackList: string[]
  dev: boolean
  dns: string
}

export interface EntryVpnSetupRequestBuilderOptions {
  getRuntimeSettings: () => EntryVpnRuntimeSettings
}

interface EntryVpnSetupBaseRequest {
  ip: string
  mask: number
  magicDNS: boolean
  instanceId: string
  needExitNode: boolean
  routes?: string[]
}

export class EntryVpnSetupRequestBuilder {
  private readonly getRuntimeSettings: () => EntryVpnRuntimeSettings

  constructor(options: EntryVpnSetupRequestBuilderOptions) {
    this.getRuntimeSettings = options.getRuntimeSettings
  }

  buildFromEventData(data: emitter.EventData): EntryVpnSetupRequest {
    const ip = data.data!.ip as string
    const mask = data.data!.mask as number
    const magicDNS = data.data!.magicDNS as boolean
    const instanceId = data.data!.id as string
    const needExitNode = data.data!.needExitNode as boolean
    const routes = data.data!.routes as string[] | undefined
    return this.withRuntimeSettings({
      ip,
      mask,
      magicDNS,
      instanceId,
      needExitNode,
      routes
    })
  }

  buildFromKernelPayload(payload: TunRequestPayload): EntryVpnSetupRequest {
    const cidr = payload.virtualIpv4Cidr ?? ''
    const ip = payload.virtualIpv4 ?? cidr.split('/')[0]
    const mask = Number(cidr.split('/')[1] ?? '24')
    const routes = payload.aggregatedRoutes ?? []
    return this.withRuntimeSettings({
      ip,
      mask,
      magicDNS: payload.magicDnsEnabled,
      instanceId: payload.instanceId,
      needExitNode: payload.needExitNode,
      routes
    })
  }

  private withRuntimeSettings(request: EntryVpnSetupBaseRequest): EntryVpnSetupRequest {
    const settings = this.getRuntimeSettings()
    return {
      ip: request.ip,
      mask: request.mask,
      magicDNS: request.magicDNS,
      instanceId: request.instanceId,
      needExitNode: request.needExitNode,
      routes: request.routes,
      vpnRoutes: settings.vpnRoutes,
      whiteList: settings.whiteList,
      blackList: settings.blackList,
      dev: settings.dev,
      dns: isIpAddr(settings.dns) ? settings.dns : DEFAULT_DNS
    }
  }
}
