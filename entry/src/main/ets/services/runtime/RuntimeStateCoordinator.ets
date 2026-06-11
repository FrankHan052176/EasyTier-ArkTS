import { InstanceInfo } from '../../class/InstanceInfo'
import { ConfigJson } from '../../config/schema/SchemaConfig'
import { RuntimeAggregateState, RuntimeInstanceState, RuntimePeerInfo } from '../../types/runtime/RuntimeTypes'
import { RuntimePeerEventPayload, TrafficStatsPayload } from '../../infrastructure/bridge/kernel/KernelBridgeTypes'
import { FavoriteCardSignatureState, RuntimeNotificationService } from './RuntimeNotificationService'
import {
  applyPeerConnDelta,
  createOptimisticRuntimeState,
  ensureRuntimePeer,
  findRuntimeStateRef,
  getValidRuntimeInstanceId
} from './RuntimeStateReducer'

const OPTIMISTIC_RUNTIME_GRACE_MS = 10000

export interface RuntimeStateCoordinatorOptions {
  runningNetworks: Map<string, RuntimeInstanceState>
  instanceInfos: Map<string, InstanceInfo>
  needTUN: Set<string>
  optimisticRunningUntil: Map<string, number>
  getInstanceName: (uuid: string) => string
  getFavoriteState: () => FavoriteCardSignatureState
  isVpnConnected: () => boolean
  isExtMode: () => boolean
}

export class RuntimeStateCoordinator {
  private runtimeNotifications: RuntimeNotificationService = new RuntimeNotificationService()
  private runtimeTrafficStatsActiveUntil: number = 0
  private readonly options: RuntimeStateCoordinatorOptions

  constructor(options: RuntimeStateCoordinatorOptions) {
    this.options = options
  }

  reset(): void {
    this.runtimeNotifications.reset()
    this.runtimeTrafficStatsActiveUntil = 0
  }

  clearRunningState(): void {
    this.options.runningNetworks.clear()
    this.options.instanceInfos.clear()
    this.options.needTUN.clear()
    this.options.optimisticRunningUntil.clear()
  }

  notifyRuntimeChanged(): void {
    this.runtimeNotifications.notifyRuntimeChanged(
      Array.from(this.options.runningNetworks.values()),
      this.options.getFavoriteState()
    )
  }

  notifyFavoriteCardChanged(force: boolean = false): void {
    this.runtimeNotifications.notifyFavoriteCardChanged(this.options.getFavoriteState(), force)
  }

  markOptimisticRunning(config: ConfigJson, displayName: string): void {
    const state = createOptimisticRuntimeState(config, displayName)
    const instanceId = state?.instanceId
    if (!state || !instanceId) {
      return
    }
    this.options.runningNetworks.set(instanceId, state)
    this.options.optimisticRunningUntil.set(instanceId, Date.now() + OPTIMISTIC_RUNTIME_GRACE_MS)
    if (!this.options.instanceInfos.has(instanceId)) {
      this.options.instanceInfos.set(instanceId, new InstanceInfo())
    }
    this.options.instanceInfos.get(instanceId)!.update(state)
    this.notifyRuntimeChanged()
  }

  removeRunningInstanceAliases(instance: RuntimeInstanceState, requestedId?: string): void {
    this.removeRunningInstanceKey(instance.instanceId)
    this.removeRunningInstanceKey(instance.configId)
    this.removeRunningInstanceKey(requestedId)
  }

  processRuntimePeerEvent(peerEvent: RuntimePeerEventPayload, fromVpn: boolean = true): void {
    if (this.shouldIgnoreExternalEvent(fromVpn)) {
      return
    }
    const peerId = peerEvent.peerId
    if (typeof peerId !== 'number') {
      return
    }
    const runtimeRef = findRuntimeStateRef(this.options.runningNetworks, peerEvent.instanceId, peerEvent.configId)
    const instanceId = runtimeRef?.state.instanceId ?? peerEvent.instanceId ?? peerEvent.configId
    if (!instanceId || instanceId.length === 0) {
      return
    }
    const instanceInfo = this.ensureInstanceInfo(instanceId)

    if (peerEvent.event === 'peer_added') {
      if (runtimeRef) {
        ensureRuntimePeer(runtimeRef.state, peerId)
        this.options.runningNetworks.set(runtimeRef.key, runtimeRef.state)
      }
      instanceInfo.addPeer(peerId)
      this.updateNotification(instanceId)
      this.notifyRuntimeChanged()
      return
    }

    if (peerEvent.event === 'peer_removed') {
      if (runtimeRef) {
        runtimeRef.state.peers = (runtimeRef.state.peers ?? []).filter((peer) => peer.peerId !== peerId)
        runtimeRef.state.routes = (runtimeRef.state.routes ?? []).filter((route) => route.peerId !== peerId)
        this.options.runningNetworks.set(runtimeRef.key, runtimeRef.state)
      }
      instanceInfo.removePeer(peerId)
      this.updateNotification(instanceId)
      this.notifyRuntimeChanged()
      return
    }

    let peer: RuntimePeerInfo = {
      peerId,
      conns: []
    }
    const route = runtimeRef?.state.routes?.find((item) => item.peerId === peerId)
    if (runtimeRef) {
      peer = ensureRuntimePeer(runtimeRef.state, peerId)
    }
    applyPeerConnDelta(peer, peerEvent.conn, peerEvent.event === 'peer_conn_added')
    if (runtimeRef) {
      this.options.runningNetworks.set(runtimeRef.key, runtimeRef.state)
    }
    instanceInfo.updatePeer(peer, route, false)
    this.updateNotification(instanceId)
    this.notifyRuntimeChanged()
  }

  processRuntimeSnapshot(snapshot: RuntimeAggregateState, fromVpn: boolean = true, includeTraffic: boolean = true): void {
    if (this.shouldIgnoreExternalEvent(fromVpn)) {
      return
    }

    const shouldUpdateTraffic = includeTraffic && Date.now() > this.runtimeTrafficStatsActiveUntil
    const instances = snapshot.instances ?? []
    const activeIds = new Set<string>()
    instances.forEach((instance) => {
      const instanceId = getValidRuntimeInstanceId(instance)
      if (!instanceId) {
        return
      }
      if (!(instance.running as boolean)) {
        return
      }
      activeIds.add(instanceId)
      if (instance.configId && instance.configId.length > 0) {
        activeIds.add(instance.configId)
      }
      if (instance.configId && instance.configId !== instanceId) {
        this.removeRunningInstanceKey(instance.configId)
      }
      this.options.optimisticRunningUntil.delete(instanceId)
      this.options.optimisticRunningUntil.delete(instance.configId)
      this.options.runningNetworks.set(instanceId, instance)
      if (!this.options.instanceInfos.has(instanceId)) {
        this.options.instanceInfos.set(instanceId, new InstanceInfo())
      }
      this.options.instanceInfos.get(instanceId)!.update(instance, shouldUpdateTraffic)
      this.updateNotification(instanceId)
    })

    for (const uuid of Array.from(this.options.runningNetworks.keys())) {
      const state = this.options.runningNetworks.get(uuid)
      const configId = state?.configId
      const isActive = activeIds.has(uuid) || (!!configId && activeIds.has(configId))
      const keepOptimistic = this.isOptimisticRunningActive(uuid) || this.isOptimisticRunningActive(configId)
      if (!isActive && !keepOptimistic) {
        this.removeRunningInstanceKey(uuid)
      }
    }

    this.notifyRuntimeChanged()
  }

  processTrafficStats(stats: TrafficStatsPayload, fromVpn: boolean = true): void {
    if (this.shouldIgnoreExternalEvent(fromVpn)) {
      return
    }

    this.runtimeTrafficStatsActiveUntil = Date.now() + 3000
    for (const instanceStats of stats.instances ?? []) {
      const instanceId = instanceStats.instanceId
      const configId = instanceStats.configId
      const state = this.options.runningNetworks.get(instanceId) ??
        this.options.runningNetworks.get(configId) ??
        Array.from(this.options.runningNetworks.values()).find((instance) => {
          return instance.instanceId === instanceId || instance.configId === configId
        })
      const key = state?.instanceId ?? instanceId ?? configId
      if (!key || key.length === 0) {
        continue
      }
      if (!this.options.instanceInfos.has(key)) {
        this.options.instanceInfos.set(key, new InstanceInfo())
      }
      this.options.instanceInfos.get(key)!.updateTraffic(instanceStats)
      this.updateNotification(key)
    }
  }

  private updateNotification(uuid: string): void {
    const info = this.options.instanceInfos.get(uuid)
    if (info) {
      this.runtimeNotifications.updateLiveText(this.options.getInstanceName(uuid), info)
    }
  }

  private isOptimisticRunningActive(instanceId: string | undefined): boolean {
    if (!instanceId) {
      return false
    }
    const until = this.options.optimisticRunningUntil.get(instanceId) ?? 0
    if (until <= Date.now()) {
      this.options.optimisticRunningUntil.delete(instanceId)
      return false
    }
    return true
  }

  private removeRunningInstanceKey(instanceId: string | undefined): void {
    if (!instanceId) {
      return
    }
    this.options.runningNetworks.delete(instanceId)
    this.options.instanceInfos.delete(instanceId)
    this.options.needTUN.delete(instanceId)
    this.options.optimisticRunningUntil.delete(instanceId)
  }

  private ensureInstanceInfo(instanceId: string): InstanceInfo {
    if (!this.options.instanceInfos.has(instanceId)) {
      this.options.instanceInfos.set(instanceId, new InstanceInfo())
    }
    return this.options.instanceInfos.get(instanceId)!
  }

  private shouldIgnoreExternalEvent(fromVpn: boolean): boolean {
    return !fromVpn && this.options.isExtMode() && this.options.isVpnConnected()
  }
}
