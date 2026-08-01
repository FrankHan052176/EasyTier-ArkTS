import { convertToProtocol, Protocol } from '../util/Conversion'
import { CircleArray } from './container/CircleArray'
import { PeerInfoDataSource } from './data_source/PeerInfoDataSource'
import { NatTypeValue, RuntimeInstanceState, RuntimePeerConnInfo, RuntimePeerInfo, RuntimeRouteView } from '../types/runtime/RuntimeTypes'
import { InstanceTrafficStats } from '../infrastructure/bridge/kernel/KernelBridgeTypes'

function tunnelTypeToProtocol(tunnelType: string): Protocol {
  const normalized = tunnelType.toLowerCase()
  const urlPrefix = normalized.split('://')[0]
  const normalizedSegments = urlPrefix.split('-')
  for (const segment of normalizedSegments) {
    const protocol = convertToProtocol(segment)
    if (protocol !== Protocol.UNKNOWN) {
      return protocol
    }
  }
  return convertToProtocol(normalized)
}

function protocolNeedsResolvedRemoteAddr(protocol: Protocol): boolean {
  return protocol === Protocol.TXT || protocol === Protocol.HTTP || protocol === Protocol.HTTPS || protocol === Protocol.SRV
}

function pickPrimaryConn(conns: RuntimePeerConnInfo[], defaultConnId?: string): RuntimePeerConnInfo | undefined {
  const defaultConn = conns.find((conn) => conn.connId === defaultConnId)
  if (defaultConn) {
    return defaultConn
  }
  const wrappedConn = conns.find((conn) => conn.tunnelType && protocolNeedsResolvedRemoteAddr(tunnelTypeToProtocol(conn.tunnelType)))
  if (wrappedConn) {
    return wrappedConn
  }
  return conns.length > 0 ? conns[0] : undefined
}

function fixedRate(value: number): number {
  if (value >= 1073741824) {
    return (value / 1073741824)
  } else if (value >= 1048576) {
    return (value / 1048576)
  } else if (value >= 1024) {
    return (value / 1024)
  } else {
    return value
  }
}

function rateUnit(value: number): string {
  if (value >= 1073741824) {
    return "GB/s"
  } else if (value >= 1048576) {
    return "MB/s"
  } else if (value >= 1024) {
    return "KB/s"
  } else {
    return "B/s"
  }
}

@ObservedV2
export class PeerInfo {
  @Trace peerId: number
  @Trace hostname: string
  @Trace cost: number
  @Trace protocol: Protocol[] = []
  @Trace latency_us: number = -1
  @Trace loss: number = 0
  @Trace byte_rate: number = 0
  @Trace byte_arr: CircleArray<number> = new CircleArray(10)
  @Trace last_bytes: number = 0
  private last_sample_at_ms: number = -1
  @Trace ip: string
  @Trace resolvedRemoteAddr: string = ''

  constructor(
    peerId: number,
    hostname: string,
    cost: number,
    ip: string
  ) {
    this.peerId = peerId
    this.hostname = hostname
    this.cost = cost
    this.ip = ip
  }

  push(byte: number, sampledAtMs: number = Date.now()): void {
    if (this.last_sample_at_ms < 0) {
      this.last_bytes = byte
      this.last_sample_at_ms = sampledAtMs
      return
    }
    if (byte < this.last_bytes) {
      this.byte_arr.clear()
      this.byte_rate = 0
      this.last_bytes = byte
      this.last_sample_at_ms = sampledAtMs
      return
    }
    const elapsedSeconds = (sampledAtMs - this.last_sample_at_ms) / 1000
    if (elapsedSeconds <= 0) {
      return
    }
    this.byte_arr.push((byte - this.last_bytes) / elapsedSeconds)
    this.last_bytes = byte
    this.last_sample_at_ms = sampledAtMs
    this.byte_rate = this.byte_arr.average
  }

  getRate(): number {
    return fixedRate(this.byte_rate)
  }

  getRateUnit(): string {
    return rateUnit(this.byte_rate)
  }

  update(newInfo: PeerInfo, includeTraffic: boolean = true) {
    this.hostname = newInfo.hostname
    this.cost = newInfo.cost
    this.ip = newInfo.ip
    this.latency_us = newInfo.latency_us
    this.protocol = newInfo.protocol
    this.loss = newInfo.loss
    this.resolvedRemoteAddr = newInfo.resolvedRemoteAddr
    if (includeTraffic) {
      this.push(newInfo.last_bytes)
    }
  }

  updateTraffic(totalBytes: number, latencyUs: number, lossRate: number, sampledAtMs: number = Date.now()): void {
    if (latencyUs >= 0) {
      this.latency_us = latencyUs
    }
    this.loss = lossRate
    this.push(totalBytes, sampledAtMs)
  }
}

@ObservedV2
export class InstanceInfo {
  @Trace peers: PeerInfoDataSource = new PeerInfoDataSource()
  @Trace private download_rate: number = 0
  @Trace private download_arr: CircleArray<number> = new CircleArray(10)
  @Trace private last_download: number = -1
  @Trace private upload_rate: number = 0
  @Trace private upload_arr: CircleArray<number> = new CircleArray(10)
  @Trace private last_upload: number = -1
  private last_traffic_sample_at_ms: number = -1
  @Trace udp_nat: NatTypeValue = NatTypeValue.Unknown
  @Trace tcp_nat: NatTypeValue = NatTypeValue.Unknown
  @Trace ip: string = "waiting"

  private buildPeerInfo(peerId: number, route?: RuntimeRouteView, peer?: RuntimePeerInfo): PeerInfo {
    const peerInfo = new PeerInfo(peerId, route?.hostname ?? "N/A", route?.cost ?? 0, route?.ipv4 ?? "waiting")
    let bytes = 0
    let loss = 0
    let latency_us = 99999999999
    let protocols: Protocol[] = []
    let resolvedRemoteAddr = ''
    const peerConns = peer?.conns ?? []
    for (const conn of peerConns) {
      if (conn.stats) {
        bytes += conn.stats.rxBytes + conn.stats.txBytes
        latency_us = Math.min(conn.stats.latencyUs, latency_us)
      }
      loss = Math.max(conn.lossRate ?? 0, loss)
    }
    const primaryConn = pickPrimaryConn(peerConns, peer?.defaultConnId)
    if (primaryConn?.tunnelType) {
      const protocol = tunnelTypeToProtocol(primaryConn.tunnelType)
      if (protocol !== Protocol.UNKNOWN) {
        protocols = [protocol]
      }
      if (protocolNeedsResolvedRemoteAddr(protocol) && primaryConn.resolvedRemoteAddr) {
        resolvedRemoteAddr = primaryConn.resolvedRemoteAddr
      }
    }
    peerInfo.latency_us = latency_us
    peerInfo.loss = loss
    peerInfo.protocol = protocols
    peerInfo.resolvedRemoteAddr = resolvedRemoteAddr
    peerInfo.last_bytes = bytes
    return peerInfo
  }

  update(info: RuntimeInstanceState, includeTraffic: boolean = true) {
    //      下载  上传
    let sum = [0, 0]
    const activePeerIds: Set<number> = new Set()
    const routesByPeerId: Map<number, RuntimeRouteView> = new Map()
    for (const route of info.routes ?? []) {
      if (route) {
        routesByPeerId.set(route.peerId, route)
        activePeerIds.add(route.peerId)
      }
    }
    const peersByPeerId: Map<number, RuntimePeerInfo> = new Map()
    for (const peer of info.peers ?? []) {
      if (peer) {
        peersByPeerId.set(peer.peerId, peer)
        activePeerIds.add(peer.peerId)
      }
    }
    activePeerIds.forEach((peerId) => {
      this.peers.set(this.buildPeerInfo(peerId, routesByPeerId.get(peerId), peersByPeerId.get(peerId)), includeTraffic)
    })
    this.peers.getIds().forEach((peerId) => {
      if (!activePeerIds.has(peerId)) {
        this.peers.del(peerId)
      }
    })
    for (const peer of (info.peers ?? [])) {
      for (const conn of (peer.conns ?? [])) {
        if (conn.stats) {
          sum[0] += conn.stats.rxBytes
          sum[1] += conn.stats.txBytes
        }
      }
    }
    if (includeTraffic) {
      this.updateTrafficCounters(sum[0], sum[1])
    }

    if (info.myNodeInfo?.virtualIpv4) {
      let convertedIp = info.myNodeInfo.virtualIpv4 as string
      if (this.ip !== convertedIp) {
        this.ip = convertedIp
      }
    } else {
      this.ip = "waiting"
    }
    this.udp_nat = info.myNodeInfo?.udpNatType ?? NatTypeValue.Unknown
    this.tcp_nat = info.myNodeInfo?.tcpNatType ?? NatTypeValue.Unknown
  }

  updatePeer(peer: RuntimePeerInfo, route?: RuntimeRouteView, includeTraffic: boolean = false): void {
    this.peers.set(this.buildPeerInfo(peer.peerId, route, peer), includeTraffic)
  }

  addPeer(peerId: number): void {
    if (!this.peers.get(peerId)) {
      this.peers.set(new PeerInfo(peerId, "N/A", 0, "waiting"), false)
    }
  }

  removePeer(peerId: number): void {
    this.peers.del(peerId)
  }

  /*
    for (const route of info.routes ?? []) {
      if (route) {
        let ip = "waiting"
        if (route.ipv4) {
          ip = route.ipv4 as string
        }
        activePeerIds.add(route.peerId)
        let peerInfo = new PeerInfo(route.peerId, route.hostname ?? "N/A", route.cost ?? 0, ip)
        const peer = (info.peers ?? []).find((value: RuntimePeerInfo) => value.peerId === route.peerId)
        let bytes = 0
        let loss = 0
        let latency_us = 99999999999
        let protocols: Protocol[] = []
        let resolvedRemoteAddr = ''
        const peerConns = peer?.conns ?? []
        for (const conn of peerConns) {
          if (conn.stats) {
            bytes += conn.stats.rxBytes + conn.stats.txBytes
            latency_us = Math.min(conn.stats.latencyUs, latency_us)
          }
          loss = Math.max(conn.lossRate ?? 0, loss)
        }
        const primaryConn = pickPrimaryConn(peerConns, peer?.defaultConnId)
        if (primaryConn?.tunnelType) {
          const protocol = tunnelTypeToProtocol(primaryConn.tunnelType)
          if (protocol !== Protocol.UNKNOWN) {
            protocols = [protocol]
          }
          if (protocolNeedsResolvedRemoteAddr(protocol) && primaryConn.resolvedRemoteAddr) {
            resolvedRemoteAddr = primaryConn.resolvedRemoteAddr
          }
        }
        peerInfo.latency_us = latency_us
        peerInfo.loss = loss
        peerInfo.protocol = protocols
        peerInfo.resolvedRemoteAddr = resolvedRemoteAddr
        peerInfo.last_bytes = bytes
        this.peers.set(peerInfo, includeTraffic)
      }
    }
    this.peers.getIds().forEach((peerId) => {
      if (!activePeerIds.has(peerId)) {
        this.peers.del(peerId)
      }
    })
    for (const peer of (info.peers ?? [])) {
      for (const conn of (peer.conns ?? [])) {
        if (conn.stats) {
          sum[0] += conn.stats.rxBytes
          sum[1] += conn.stats.txBytes
        }
      }
    }
    if (includeTraffic) {
      this.updateTrafficCounters(sum[0], sum[1])
    }

    if (info.myNodeInfo?.virtualIpv4) {
      let convertedIp = info.myNodeInfo.virtualIpv4 as string
      if (this.ip !== convertedIp) {
        this.ip = convertedIp
      }
    } else {
      this.ip = "waiting"
    }
    this.udp_nat = info.myNodeInfo?.udpNatType ?? NatTypeValue.Unknown
    this.tcp_nat = info.myNodeInfo?.tcpNatType ?? NatTypeValue.Unknown
  }
  */

  updateTraffic(stats: InstanceTrafficStats, sampledAtMs: number = Date.now()): void {
    this.updateTrafficCounters(stats.rxBytes, stats.txBytes, sampledAtMs)
    for (const peer of stats.peers ?? []) {
      const peerInfo = this.peers.get(peer.peerId)
      peerInfo?.updateTraffic(peer.totalBytes, peer.latencyUs, peer.lossRate, sampledAtMs)
    }
  }

  private updateTrafficCounters(rxBytes: number, txBytes: number, sampledAtMs: number = Date.now()): void {
    if (this.last_download < 0 || this.last_upload < 0 || this.last_traffic_sample_at_ms < 0) {
      this.last_download = rxBytes
      this.last_upload = txBytes
      this.last_traffic_sample_at_ms = sampledAtMs
      return
    }
    if (rxBytes < this.last_download || txBytes < this.last_upload) {
      this.download_arr.clear()
      this.upload_arr.clear()
      this.download_rate = 0
      this.upload_rate = 0
      this.last_download = rxBytes
      this.last_upload = txBytes
      this.last_traffic_sample_at_ms = sampledAtMs
      return
    }
    const elapsedSeconds = (sampledAtMs - this.last_traffic_sample_at_ms) / 1000
    if (elapsedSeconds <= 0) {
      return
    }
    this.download_arr.push((rxBytes - this.last_download) / elapsedSeconds)
    this.upload_arr.push((txBytes - this.last_upload) / elapsedSeconds)
    this.download_rate = this.download_arr.average
    this.upload_rate = this.upload_arr.average
    this.last_download = rxBytes
    this.last_upload = txBytes
    this.last_traffic_sample_at_ms = sampledAtMs
  }

  getDownloadRate(): number {
    return fixedRate(this.download_rate)
  }

  getDownloadRateUnit(): string {
    return rateUnit(this.download_rate)
  }

  getUploadRate(): number {
    return fixedRate(this.upload_rate)
  }

  getUploadRateUnit(): string {
    return rateUnit(this.upload_rate)
  }
}
