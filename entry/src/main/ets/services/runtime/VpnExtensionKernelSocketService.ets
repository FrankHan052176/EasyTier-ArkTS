import { JSON } from '@kit.ArkTS'
import {
  KernelSocketMessage,
  KERNEL_MESSAGE_RUNTIME_PEER_EVENT,
  KERNEL_MESSAGE_RUNTIME_TOPOLOGY,
  KERNEL_MESSAGE_TRAFFIC_STATS,
  KERNEL_MESSAGE_TUN_REQUEST,
  TunRequestPayload
} from '../../infrastructure/bridge/kernel/KernelBridgeTypes'
import { KernelSocketClient } from '../../infrastructure/bridge/kernel/KernelSocketClient'
import { Logger } from '../../shared/logging/Logger'

export interface VpnExtensionKernelSocketServiceOptions {
  logTarget: Object | string
  onTunRequest: (payload: TunRequestPayload, trigger: string) => void
  broadcastRaw: (rawMessage: string) => void
}

export class VpnExtensionKernelSocketService {
  private readonly logTarget: Object | string
  private readonly onTunRequest: (payload: TunRequestPayload, trigger: string) => void
  private readonly broadcastRaw: (rawMessage: string) => void
  private kernelSocketClient: KernelSocketClient | undefined = undefined

  constructor(options: VpnExtensionKernelSocketServiceOptions) {
    this.logTarget = options.logTarget
    this.onTunRequest = options.onTunRequest
    this.broadcastRaw = options.broadcastRaw
  }

  connect(socketPath: string): void {
    this.close()
    this.kernelSocketClient = new KernelSocketClient()
    this.kernelSocketClient.start({
      socketPath,
      logTarget: this.logTarget,
      onConnected: () => {
        Logger.info('Connected to kernel socket', this.logTarget)
      },
      onMessage: (msg: KernelSocketMessage) => {
        this.handleMessage(msg)
      }
    })
  }

  close(): void {
    this.kernelSocketClient?.close()
    this.kernelSocketClient = undefined
  }

  private handleMessage(msg: KernelSocketMessage): void {
    if (msg.messageType === KERNEL_MESSAGE_TUN_REQUEST) {
      const payload = typeof msg.payloadJson === 'string' ? JSON.parse(msg.payloadJson) as TunRequestPayload : msg.payloadJson as TunRequestPayload
      this.onTunRequest(payload, KERNEL_MESSAGE_TUN_REQUEST)
    } else if (msg.messageType === KERNEL_MESSAGE_RUNTIME_TOPOLOGY ||
      msg.messageType === KERNEL_MESSAGE_RUNTIME_PEER_EVENT ||
      msg.messageType === KERNEL_MESSAGE_TRAFFIC_STATS) {
      const payloadJson = typeof msg.payloadJson === 'string' ? msg.payloadJson : JSON.stringify(msg.payloadJson)
      this.broadcastRaw(`{"type":"${msg.messageType}","data":${payloadJson}}\n`)
    }
  }
}
