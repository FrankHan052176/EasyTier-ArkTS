import { convertToProtocol, Protocol } from '../util/Conversion'
import { CircleArray } from './container/CircleArray'
import { PeerInfoDataSource } from './data_source/PeerInfoDataSource'
import { NatTypeValue, RuntimeInstanceState, RuntimePeerInfo } from '../types/runtime/RuntimeTypes'

function fixedRate(value: number): number {
  if (value > 107374182) {
    return (value / 1073741824)
  } else if (value > 104858) {
    return (value / 1048576)
  } else if (value > 102) {
    return (value / 1024)
  } else {
    return value
  }
}

function rateUnit(value: number): string {
  if (value > 107374182) {
    return "GB/s"
  } else if (value > 104858) {
    return "MB/s"
  } else if (value > 102) {
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
  @Trace ip: string

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

  push(byte: number) {
    this.byte_arr.push(byte - this.last_bytes)
    this.last_bytes = byte
    this.byte_rate = this.byte_arr.sum
  }

  getRate(): number {
    return fixedRate(this.byte_rate)
  }

  getRateUnit(): string {
    return rateUnit(this.byte_rate)
  }

  update(newInfo: PeerInfo) {
    this.cost = newInfo.cost
    this.latency_us = newInfo.latency_us
    this.protocol = newInfo.protocol
    this.loss = newInfo.loss
    this.push(newInfo.last_bytes)
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
  @Trace udp_nat: NatTypeValue = NatTypeValue.Unknown
  @Trace tcp_nat: NatTypeValue = NatTypeValue.Unknown
  @Trace ip: string = "waiting"

  update(info: RuntimeInstanceState) {
    //      下载  上传
    let sum = [0, 0]
    for (const route of info.routes ?? []) {
      if (route) {
        let ip = "waiting"
        if (route.ipv4) {
          ip = route.ipv4 as string
        }
        let peerInfo = new PeerInfo(route.peerId, route.hostname ?? "N/A", route.cost ?? 0, ip)
        const peer = (info.peers ?? []).find((value: RuntimePeerInfo) => value.peerId === route.peerId)
        let bytes = 0
        let loss = 0
        let latency_us = 99999999999
        let protocols: Set<Protocol> = new Set
        for (const conn of (peer?.conns ?? [])) {
          if (conn.stats) {
            bytes += conn.stats.rxBytes + conn.stats.txBytes
            latency_us = Math.min(conn.stats.latencyUs, latency_us)
          }
          if (conn.tunnelType) {
            protocols.add(convertToProtocol(conn.tunnelType.toLowerCase()))
            loss = Math.max(conn.lossRate ?? 0, loss)
          }
        }
        peerInfo.latency_us = latency_us
        peerInfo.loss = loss
        peerInfo.protocol = Array.from(protocols)
        peerInfo.last_bytes = bytes
        this.peers.set(peerInfo)
      }
    }
    for (const peer of (info.peers ?? [])) {
      for (const conn of (peer.conns ?? [])) {
        if (conn.stats) {
          sum[0] += conn.stats.rxBytes
          sum[1] += conn.stats.txBytes
        }
      }
    }
    if (this.last_download < 0) {
      this.last_download = sum[0]
    } else {
      const deltaDownload = Math.max(0, sum[0] - this.last_download)
      this.download_arr.push(deltaDownload)
      this.download_rate = this.download_arr.sum
      this.last_download = sum[0]
    }

    if (this.last_upload < 0) {
      this.last_upload = sum[1]
    } else {
      const deltaUpload = Math.max(0, sum[1] - this.last_upload)
      this.upload_arr.push(deltaUpload)
      this.upload_rate = this.upload_arr.sum
      this.last_upload = sum[1]
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
