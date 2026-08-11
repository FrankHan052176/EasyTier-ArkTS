import { deviceInfo } from '@kit.BasicServicesKit'
import { connection, vpnExtension } from '@kit.NetworkKit'
import { NetworkSegment } from '../../models/network/NetworkSegment'
import { stringArr2RouteArr } from '../../util/Conversion'
import { APP_BUNDLE_NAME } from '../runtime/AbilityRuntimePolicy'

const DEFAULT_DNS_ADDRESS = '223.5.5.5'
const MAGIC_DNS_ADDRESS = '100.100.100.101'
const IPV4_FAMILY = 1
const DEFAULT_TUN_MTU = 1380

export interface TunRouteBuildOptions {
  ip: string
  magicDNS: boolean
  needExitNode: boolean
  routeStrings?: string[]
  enabled: boolean
  forceGlobal?: boolean
  ignoreInvalidRoutes?: boolean
}

export interface TunRouteBuildResult {
  routes?: connection.RouteInfo[]
  parsedRoutes: NetworkSegment[]
}

export interface TunVpnConfigBuildOptions extends TunRouteBuildOptions {
  mask: number
  whiteList: boolean
  blackList: string[]
  dev: boolean
  dnsAddress: string
}

export interface TunVpnConfigBuildResult extends TunRouteBuildResult {
  vpnConfig: vpnExtension.VpnConfig
}

export function shouldBuildPreferenceVpnRoutes(vpnRoutes: boolean, sdkApiVersion: number = deviceInfo.sdkApiVersion): boolean {
  return vpnRoutes || sdkApiVersion >= 20
}

export function buildTunVpnAppList(blackList: string[], sdkApiVersion: number = deviceInfo.sdkApiVersion): string[] {
  return [
    sdkApiVersion >= 22 ? '' : APP_BUNDLE_NAME,
    ...blackList
  ]
}

export function parseTunRouteStrings(routeStrings?: string[], ignoreInvalidRoutes: boolean = false): NetworkSegment[] {
  const parsedRoutes: NetworkSegment[] = []
  routeStrings?.forEach((route) => {
    if (ignoreInvalidRoutes) {
      try {
        parsedRoutes.push(new NetworkSegment(route))
      } catch (_) {
      }
    } else {
      parsedRoutes.push(new NetworkSegment(route))
    }
  })
  return parsedRoutes
}

export function buildTunRoutes(options: TunRouteBuildOptions): TunRouteBuildResult {
  const parsedRoutes = parseTunRouteStrings(options.routeStrings, options.ignoreInvalidRoutes ?? false)
  const routes = options.enabled ? stringArr2RouteArr(
    options.ip,
    options.magicDNS,
    options.needExitNode,
    parsedRoutes,
    options.forceGlobal
  ) : undefined
  return {
    routes,
    parsedRoutes
  }
}

export function buildTunVpnConfig(options: TunVpnConfigBuildOptions): TunVpnConfigBuildResult {
  const appList = buildTunVpnAppList(options.blackList)
  const routeResult = buildTunRoutes(options)
  const dnsAddresses: string[] | undefined = options.magicDNS ? [MAGIC_DNS_ADDRESS] :
    (options.dev ? [options.dnsAddress || DEFAULT_DNS_ADDRESS] : undefined)
  return {
    routes: routeResult.routes,
    parsedRoutes: routeResult.parsedRoutes,
    vpnConfig: {
      addresses: [
        {
          address: {
            address: options.ip,
            family: IPV4_FAMILY
          },
          prefixLength: options.mask
        }
      ],
      blockedApplications: options.whiteList ? [] : appList,
      trustedApplications: options.whiteList ? appList : [],
      dnsAddresses,
      mtu: DEFAULT_TUN_MTU,
      routes: routeResult.routes
    }
  }
}
