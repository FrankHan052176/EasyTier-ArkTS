import { NetworkSegment } from '../../../models/network/NetworkSegment'

function ipv4ToNumber(ip: string): number {
  const parts = ip.split('.')
  if (parts.length !== 4) {
    return 0
  }
  let result = 0
  for (let index = 0; index < parts.length; index++) {
    const value = Number.parseInt(parts[index], 10)
    if (!Number.isFinite(value) || value < 0 || value > 255) {
      return 0
    }
    result = result * 256 + value
  }
  return result
}

export function normalizeRouteStrings(routes: string[]): string[] {
  const normalized: string[] = []
  const seen: Set<string> = new Set()
  routes.forEach((route) => {
    try {
      const segment = new NetworkSegment(route.trim())
      const routeKey = segment.toString()
      if (seen.has(routeKey)) {
        return
      }
      seen.add(routeKey)
      normalized.push(routeKey)
    } catch (_) {
    }
  })
  normalized.sort((left: string, right: string): number => {
    const leftParts = left.split('/')
    const rightParts = right.split('/')
    const addressDelta = ipv4ToNumber(leftParts[0]) - ipv4ToNumber(rightParts[0])
    if (addressDelta !== 0) {
      return addressDelta
    }
    return Number.parseInt(leftParts[1] ?? '0', 10) - Number.parseInt(rightParts[1] ?? '0', 10)
  })
  return normalized
}

export function routeSignature(routes: string[]): string {
  return JSON.stringify(normalizeRouteStrings(routes))
}
