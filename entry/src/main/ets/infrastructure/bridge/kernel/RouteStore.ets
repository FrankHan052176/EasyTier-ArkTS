import { RuntimeAggregateState, RuntimeInstanceState } from '../../../types/runtime/RuntimeTypes'

export interface RuntimeTunUpdate {
  ip: string
  mask: number
  magicDNS: boolean
  needExitNode: boolean
  routes: string[]
}

export function routeSignature(routes: string[]): string {
  return JSON.stringify(routes)
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
  const result: RuntimeTunUpdate = {
    ip: ip,
    mask: Number(cidr.split('/')[1] ?? '24'),
    magicDNS: instance?.magicDnsEnabled ?? false,
    needExitNode: instance?.needExitNode ?? false,
    routes: tun?.aggregatedRoutes ?? []
  }
  return result
}
