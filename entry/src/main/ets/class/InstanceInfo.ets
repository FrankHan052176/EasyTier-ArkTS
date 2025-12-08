import { NetworkInstanceRunningInfo } from '../protobuf/api_manage'
import { convertToProtocol, Protocol } from '../util/ETConfig'
import { CircleArray } from './container/CircleArray'
import { PeerInfoDataSource } from './PeerInfoDataSource'
import { convertAddrToIp } from '../util/Conversion'

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
  @Trace private download_rate: number = 0
  @Trace private download_arr: CircleArray<number> = new CircleArray(10)
  @Trace private last_download: number = 0
  @Trace private upload_rate: number = 0
  @Trace private upload_arr: CircleArray<number> = new CircleArray(10)
  @Trace private last_upload: number = 0
  @Trace peers: PeerInfoDataSource = new PeerInfoDataSource()

  update(info: NetworkInstanceRunningInfo) {
    //      下载  上传
    let sum = [0, 0]
    for (const pair of info.peer_route_pairs) {
      if (pair.route) {
        let ip = "waiting"
        if (pair.route.ipv4_addr?.address?.addr) {
          ip = convertAddrToIp(pair.route.ipv4_addr?.address?.addr)
        }
        let peerInfo = new PeerInfo(pair.route.peer_id, pair.route.hostname, pair.route.cost, ip)
        let bytes = 0
        let loss = 0
        let latency_us = 99999999999
        let protocols: Protocol[] = []
        for (const conn of pair.peer?.conns ?? []) {
          if (conn.stats) {
            bytes += conn.stats.rx_bytes + conn.stats.tx_bytes
            latency_us = Math.min(conn.stats.latency_us, latency_us)
          }
          if (conn.tunnel) {
            protocols.push(convertToProtocol(conn.tunnel.tunnel_type))
            loss = Math.max(conn.loss_rate, loss)
          }
        }
        peerInfo.latency_us = latency_us
        peerInfo.loss = loss
        peerInfo.protocol = protocols
        peerInfo.last_bytes = bytes
        this.peers.set(peerInfo)
      }
      if (pair.peer) {
        for (const conn of pair.peer.conns) {
          if (conn.stats) {
            sum[0] += conn.stats.rx_bytes
            sum[1] += conn.stats.tx_bytes
          }
        }
      }
    }
    this.download_arr.push(sum[0] - this.last_download)
    this.last_download = sum[0]
    this.download_rate = this.download_arr.sum
    this.upload_arr.push(sum[1] - this.last_upload)
    this.last_upload = sum[1]
    this.upload_rate = this.upload_arr.sum
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