import { ConfigJson } from '../../config/schema/SchemaConfig'
import {
  RuntimeInstanceState,
  RuntimePeerConnInfo,
  RuntimePeerInfo
} from '../../types/runtime/RuntimeTypes'

export interface RuntimeStateRef {
  key: string
  state: RuntimeInstanceState
}

export function getValidRuntimeInstanceId(instance: RuntimeInstanceState): string | undefined {
  const instanceId = instance.instanceId
  if (typeof instanceId !== 'string' || instanceId.length === 0) {
    return undefined
  }
  return instanceId
}

export function buildRuntimeNotifySignature(instances: RuntimeInstanceState[]): string {
  return instances
    .map((instance) => {
      const instanceId = getValidRuntimeInstanceId(instance) ?? ''
      let connCount = 0
      for (const peer of instance.peers ?? []) {
        connCount += peer.conns?.length ?? 0
      }
      return [
        instanceId,
        instance.configId ?? '',
        instance.running ? '1' : '0',
        instance.tunAttached ? '1' : '0',
        instance.myNodeInfo?.virtualIpv4 ?? '',
        `${instance.peers.length}`,
        `${connCount}`,
        `${instance.routes.length}`
      ].join(':')
    })
    .sort()
    .join('|')
}

export function findRuntimeStateRef(
  runningNetworks: Map<string, RuntimeInstanceState>,
  instanceId: string | undefined,
  configId: string | undefined
): RuntimeStateRef | undefined {
  const directKeys: string[] = []
  if (instanceId && instanceId.length > 0) {
    directKeys.push(instanceId)
  }
  if (configId && configId.length > 0 && configId !== instanceId) {
    directKeys.push(configId)
  }
  for (const key of directKeys) {
    const state = runningNetworks.get(key)
    if (state) {
      return { key, state }
    }
  }
  for (const key of Array.from(runningNetworks.keys())) {
    const state = runningNetworks.get(key)
    if (!state) {
      continue
    }
    const instanceMatches = !!instanceId && (state.instanceId === instanceId || state.configId === instanceId)
    const configMatches = !!configId && (state.instanceId === configId || state.configId === configId)
    if (instanceMatches || configMatches) {
      return { key, state }
    }
  }
  return undefined
}

export function ensureRuntimePeer(state: RuntimeInstanceState, peerId: number): RuntimePeerInfo {
  state.peers = state.peers ?? []
  let peer = state.peers.find((item) => item.peerId === peerId)
  if (!peer) {
    peer = {
      peerId,
      conns: []
    }
    state.peers.push(peer)
  }
  return peer
}

function normalizePeerConn(peerId: number, conn: RuntimePeerConnInfo | undefined): RuntimePeerConnInfo | undefined {
  if (!conn) {
    return undefined
  }
  if (conn.peerId === undefined) {
    conn.peerId = peerId
  }
  return conn
}

function updateDirectConnIds(peer: RuntimePeerInfo, connId: string | undefined, add: boolean): void {
  if (!connId || connId.length === 0) {
    return
  }
  const ids = peer.directlyConnectedConns ?? []
  if (add) {
    if (ids.indexOf(connId) < 0) {
      ids.push(connId)
    }
    peer.directlyConnectedConns = ids
    return
  }
  peer.directlyConnectedConns = ids.filter((id) => id !== connId)
}

export function applyPeerConnDelta(peer: RuntimePeerInfo, rawConn: RuntimePeerConnInfo | undefined, add: boolean): void {
  peer.conns = peer.conns ?? []
  const conn = normalizePeerConn(peer.peerId, rawConn)
  if (!conn) {
    return
  }
  const connId = conn.connId
  if (add) {
    if (connId && connId.length > 0) {
      const index = peer.conns.findIndex((item) => item.connId === connId)
      if (index >= 0) {
        peer.conns[index] = conn
      } else {
        peer.conns.push(conn)
      }
      if (!peer.defaultConnId || peer.defaultConnId.length === 0) {
        peer.defaultConnId = connId
      }
      updateDirectConnIds(peer, connId, true)
    } else {
      peer.conns.push(conn)
    }
    return
  }
  if (connId && connId.length > 0) {
    peer.conns = peer.conns.filter((item) => item.connId !== connId)
    if (peer.defaultConnId === connId) {
      peer.defaultConnId = peer.conns.length > 0 ? peer.conns[0].connId : undefined
    }
    updateDirectConnIds(peer, connId, false)
  } else {
    peer.conns = peer.conns.filter((item) => item.peerId !== peer.peerId)
    peer.defaultConnId = peer.conns.length > 0 ? peer.conns[0].connId : undefined
    peer.directlyConnectedConns = []
  }
}

export function createOptimisticRuntimeState(config: ConfigJson, displayName: string): RuntimeInstanceState | undefined {
  const instanceId = config.instance_id as string | undefined
  if (!instanceId) {
    return undefined
  }
  const networkLength = Number(config.network_length ?? 24)
  const virtualIpv4 = typeof config.virtual_ipv4 === 'string' ? config.virtual_ipv4 as string : undefined
  return {
    configId: instanceId,
    instanceId,
    displayName,
    running: true,
    tunRequired: !Boolean(config.no_tun),
    tunAttached: false,
    magicDnsEnabled: Boolean(config.enable_magic_dns),
    needExitNode: Array.isArray(config.exit_nodes) && config.exit_nodes.length > 0,
    myNodeInfo: {
      virtualIpv4,
      virtualIpv4Cidr: virtualIpv4 ? `${virtualIpv4}/${networkLength}` : undefined,
    },
    routes: [],
    peers: []
  }
}

export function findRunningInstance(
  runningNetworks: Map<string, RuntimeInstanceState>,
  uuid?: string
): RuntimeInstanceState | undefined {
  if (!uuid || uuid.length === 0) {
    return undefined
  }
  const direct = runningNetworks.get(uuid)
  if (direct) {
    return direct
  }
  return Array.from(runningNetworks.values()).find((instance) => {
    return instance.configId === uuid || instance.instanceId === uuid
  })
}

export function listRunningInstances(runningNetworks: Map<string, RuntimeInstanceState>): RuntimeInstanceState[] {
  const dedup = new Map<string, RuntimeInstanceState>()
  Array.from(runningNetworks.values()).forEach((instance) => {
    const key = instance.configId && instance.configId.length > 0 ? instance.configId : instance.instanceId
    dedup.set(key, instance)
  })
  return Array.from(dedup.values())
}
