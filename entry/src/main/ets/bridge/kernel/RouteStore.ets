import { NetworkSegment } from '../../models/network/NetworkSegment'
import { RuntimeAggregateState, RuntimeInstanceState } from '../../types/runtime/RuntimeTypes'

export interface RouteMergeResult {
  routes: string[]
  changed: boolean
}

export interface RuntimeTunUpdate {
  ip: string
  mask: number
  magicDNS: boolean
  needExitNode: boolean
  routes: string[]
}

function sortSegments(routes: NetworkSegment[]): NetworkSegment[] {
  return routes.sort((left, right) => {
    if (left.prefix !== right.prefix) {
      return left.prefix - right.prefix
    }
    return left.toString().localeCompare(right.toString())
  })
}

function parseSegments(routes: string[]): NetworkSegment[] {
  const parsed: NetworkSegment[] = []
  routes.forEach((route) => {
    try {
      parsed.push(new NetworkSegment(route))
    } catch (_) {
    }
  })
  return parsed
}

function simplifySegments(routes: NetworkSegment[]): NetworkSegment[] {
  const simplified: NetworkSegment[] = []
  sortSegments(routes).forEach((route) => {
    const routeStr = route.toString()
    if (simplified.some((existing) => existing.contains(routeStr))) {
      return
    }
    for (let index = simplified.length - 1; index >= 0; index--) {
      if (route.contains(simplified[index].toString())) {
        simplified.splice(index, 1)
      }
    }
    simplified.push(route)
  })
  return simplified
}

export function normalizeRouteStrings(routes: string[]): string[] {
  const unique = new Set<string>()
  const normalized: string[] = []
  simplifySegments(parseSegments(routes)).forEach((route) => {
    const routeStr = route.toString()
    if (!unique.has(routeStr)) {
      unique.add(routeStr)
      normalized.push(routeStr)
    }
  })
  return normalized
}

export function routeSignature(routes: string[]): string {
  return JSON.stringify(normalizeRouteStrings(routes))
}

export function buildBaseRoutes(aggregatedRoutes: string[], virtualIpv4Cidr?: string): string[] {
  const routes = [...aggregatedRoutes]
  if (virtualIpv4Cidr && virtualIpv4Cidr.length > 0) {
    routes.unshift(virtualIpv4Cidr)
  }
  return normalizeRouteStrings(routes)
}

export function mergeMissingProxyRoutes(existingRoutes: string[], proxyCidrs: string[]): RouteMergeResult {
  const normalizedExisting = normalizeRouteStrings(existingRoutes)
  const currentSegments = parseSegments(normalizedExisting)
  let changed = false

  proxyCidrs.forEach((cidr) => {
    let proxyRoute: NetworkSegment
    try {
      proxyRoute = new NetworkSegment(cidr)
    } catch (_) {
      return
    }
    const proxyStr = proxyRoute.toString()
    if (currentSegments.some((existing) => existing.contains(proxyStr))) {
      return
    }
    currentSegments.push(proxyRoute)
    changed = true
  })

  const result: RouteMergeResult = {
    routes: changed ? normalizeRouteStrings(currentSegments.map((route) => route.toString())) : normalizedExisting,
    changed: changed
  }
  return result
}

export function collectPeerProxyCidrs(instance?: RuntimeInstanceState): string[] {
  const proxyCidrs: string[] = []
  ;(instance?.routes ?? []).forEach((route) => {
    ;(route.proxyCidrs ?? []).forEach((cidr) => {
      proxyCidrs.push(cidr)
    })
  })
  return proxyCidrs
}

export function buildRuntimeTunUpdate(snapshot: RuntimeAggregateState, instanceId?: string): RuntimeTunUpdate | undefined {
  const tun = snapshot.tun
  if (!tun?.active || !instanceId || (tun.attachedInstanceIds ?? []).indexOf(instanceId) < 0) {
    return undefined
  }
  const instance = (snapshot.instances ?? []).find((value) => value.instanceId === instanceId)
  const cidr = instance?.myNodeInfo?.virtualIpv4Cidr
  const ip = instance?.myNodeInfo?.virtualIpv4
  if (!cidr || !ip) {
    return undefined
  }
  const baseRoutes = buildBaseRoutes(tun?.aggregatedRoutes ?? [], cidr)
  const merged = mergeMissingProxyRoutes(baseRoutes, collectPeerProxyCidrs(instance))
  const result: RuntimeTunUpdate = {
    ip: ip,
    mask: Number(cidr.split('/')[1] ?? '24'),
    magicDNS: instance?.magicDnsEnabled ?? false,
    needExitNode: instance?.needExitNode ?? false,
    routes: merged.routes
  }
  return result
}
