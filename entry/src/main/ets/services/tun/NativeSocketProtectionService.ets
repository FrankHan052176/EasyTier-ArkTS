import { vpnExtension } from '@kit.NetworkKit'
import easytier from 'easytier-ohrs'
import { Logger } from '../../shared/logging/Logger'

interface NativeSocketProtectionRequest {
  requestId: string
  socketFd: number
  purpose: string
}

/**
 * Bridges Core's socket-creation hook to HarmonyOS VpnConnection.protect().
 *
 * Core keeps a duplicate descriptor alive until this service acknowledges the
 * request, so every selected transport socket is protected before connect/send
 * without applying VPN bypass to the entire process.
 */
export class NativeSocketProtectionService {
  private readonly getVpnConnection: () => vpnExtension.VpnConnection | undefined
  private readonly logTarget: Object | string
  private readonly onFatal: ((error: Error) => void) | undefined
  private active: boolean = false
  private generation: number = 0
  private loopPromise: Promise<void> | undefined = undefined
  private stopPromise: Promise<void> | undefined = undefined
  private connectionOperationQueue: Promise<void> = Promise.resolve()

  constructor(getVpnConnection: () => vpnExtension.VpnConnection | undefined, logTarget: Object | string,
    onFatal?: (error: Error) => void) {
    this.getVpnConnection = getVpnConnection
    this.logTarget = logTarget
    this.onFatal = onFatal
  }

  async start(): Promise<void> {
    if (this.active) {
      return
    }
    if (!easytier.enableSocketProtection()) {
      throw new Error('enable_socket_protection_failed')
    }
    this.active = true
    const generation = ++this.generation
    const loop = this.run(generation).catch((error: Error) => {
      if (this.active && this.generation === generation) {
        this.active = false
        easytier.failSocketProtection()
        this.onFatal?.(error)
      }
      Logger.error(`socket protection loop failed: ${error.message}`, this.logTarget)
    })
    this.loopPromise = loop
    Logger.info('per-socket VPN protection enabled', this.logTarget)
  }

  async stop(): Promise<void> {
    const stopping = this.stopPromise
    if (stopping) {
      return await stopping
    }
    if (!this.active && this.loopPromise === undefined) {
      return
    }
    const stopPromise = this.finishStop()
    this.stopPromise = stopPromise
    return stopPromise.then(() => {
      if (this.stopPromise === stopPromise) {
        this.stopPromise = undefined
      }
    }, (error: Error) => {
      if (this.stopPromise === stopPromise) {
        this.stopPromise = undefined
      }
      throw error
    })
  }

  runConnectionOperation<T>(operation: () => Promise<T>): Promise<T> {
    const task = this.connectionOperationQueue.catch(() => {}).then(operation)
    this.connectionOperationQueue = task.then(() => {}, () => {})
    return task
  }

  private async finishStop(): Promise<void> {
    this.active = false
    this.generation++
    easytier.disableSocketProtection()
    const loop = this.loopPromise
    if (loop) {
      await loop
    }
    if (this.loopPromise === loop) {
      this.loopPromise = undefined
    }
    Logger.info('per-socket VPN protection disabled', this.logTarget)
  }

  private async run(generation: number): Promise<void> {
    while (this.active && this.generation === generation) {
      const request = await easytier.nextSocketProtectionRequest() as NativeSocketProtectionRequest | null
      if (!request) {
        if (this.active && this.generation === generation) {
          throw new Error('socket_protection_request_stream_closed')
        }
        return
      }
      if (!this.active || this.generation !== generation) {
        easytier.completeSocketProtection(request.requestId, false, 'socket_protection_stopped')
        return
      }
      let success = false
      let error: string | undefined = undefined
      try {
        await this.runConnectionOperation(async () => {
          const vpnConnection = this.getVpnConnection()
          if (!vpnConnection) {
            throw new Error('vpn_connection_unavailable')
          }
          await vpnConnection.protect(request.socketFd)
        })
        success = true
      } catch (protectError) {
        error = (protectError as Error).message
      }
      const completed = easytier.completeSocketProtection(request.requestId, success, error)
      if (!completed) {
        // Core retains the duplicate FD until this acknowledgement, but the
        // socket-creation task may already be cancelled. There is no live caller
        // to receive this result; keep protecting the remaining sockets.
        Logger.debug(`socket protection requester already released request=${request.requestId} purpose=${request.purpose}`,
          this.logTarget)
        continue
      }
      if (!success) {
        Logger.error(`socket protection failed request=${request.requestId} purpose=${request.purpose}: ${error ?? ''}`,
          this.logTarget)
        throw new Error(`socket_protection_failed:${request.purpose}:${error ?? 'unknown'}`)
      }
    }
  }
}
