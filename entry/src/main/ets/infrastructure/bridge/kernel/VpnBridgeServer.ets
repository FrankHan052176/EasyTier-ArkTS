import { buffer } from '@kit.ArkTS'
import { fileIo } from '@kit.CoreFileKit'
import { BusinessError } from '@kit.BasicServicesKit'
import { socket } from '@kit.NetworkKit'
import { Logger } from '../../../shared/logging/Logger'
import {
  VpnContinueStateData,
  VpnLogData,
  VpnMessage,
  VpnRuntimeStartRequestData,
  VpnRuntimeStartResultData,
  KERNEL_MESSAGE_RUNTIME_TOPOLOGY,
  KERNEL_MESSAGE_TRAFFIC_STATS,
  VPN_MESSAGE_CONTINUE_STATE,
  VPN_MESSAGE_LOGS,
  VPN_MESSAGE_RUNTIME_START_REQUEST,
  VPN_MESSAGE_RUNTIME_START_RESULT
} from './KernelBridgeTypes'
import { decodeSocketChunk, parseVpnBridgeMessage } from './SocketCodec'

const VPN_LOG_FORWARD_MAX_LINES = 80
const VPN_LOG_FORWARD_MAX_CHARS = 12000

function trimForwardLogs(logs: string[]): string[] {
  if (logs.length <= VPN_LOG_FORWARD_MAX_LINES) {
    return logs
  }
  const result: string[] = []
  let chars = 0
  for (let index = logs.length - 1; index >= 0 && result.length < VPN_LOG_FORWARD_MAX_LINES; index--) {
    const line = logs[index]
    chars += line.length
    if (chars > VPN_LOG_FORWARD_MAX_CHARS && result.length > 0) {
      break
    }
    result.unshift(line)
  }
  return result
}

export class VpnBridgeServer {
  private readonly logTarget: Object | string
  private server: socket.LocalSocketServer | undefined
  private connections: Map<number, socket.LocalSocketConnection> = new Map()
  private continuationActive: boolean = false
  private latestTopologyRaw: string = ''
  private latestTrafficRaw: string = ''
  private latestStartResultRaw: string = ''
  private runtimeGeneration: number = 0
  private latestTopologyGeneration: number = -1
  private latestTrafficGeneration: number = -1
  private latestStartResultGeneration: number = -1
  private readonly onRuntimeStartRequest: ((request: VpnRuntimeStartRequestData) => void) | undefined

  constructor(logTarget: Object | string, onRuntimeStartRequest?: (request: VpnRuntimeStartRequestData) => void) {
    this.logTarget = logTarget
    this.onRuntimeStartRequest = onRuntimeStartRequest
  }

  get connectionCount(): number {
    return this.connections.size
  }

  start(socketFilesDir: string, socketName: string): void {
    this.server = socket.constructLocalSocketServerInstance()
    const sandboxPath = `${socketFilesDir}/${socketName}`
    try {
      fileIo.unlinkSync(sandboxPath)
    } catch (_) {
    }

    const listenAddr: socket.LocalAddress = {
      address: sandboxPath
    }
    this.server.listen(listenAddr).then(() => {
      Logger.debug(`VpnServer listening on ${sandboxPath}`, this.logTarget)
    }).catch((err: object) => {
      Logger.error(`VpnServer listen error: ${JSON.stringify(err)}`, this.logTarget)
    })

    this.server.on('connect', (connection: socket.LocalSocketConnection) => {
      let requestBuffer = ''
      Logger.debug('UI process connected to VpnServer', this.logTarget)
      this.connections.set(connection.clientId, connection)
      this.sendBridgeMessage(connection, {
        type: VPN_MESSAGE_CONTINUE_STATE,
        data: { active: this.continuationActive } as VpnContinueStateData
      })
      if (this.latestTopologyRaw.length > 0 && this.latestTopologyGeneration === this.runtimeGeneration) {
        this.sendRawBridgeMessage(connection, this.latestTopologyRaw)
      }
      if (this.latestTrafficRaw.length > 0 && this.latestTrafficGeneration === this.runtimeGeneration) {
        this.sendRawBridgeMessage(connection, this.latestTrafficRaw)
      }
      if (this.latestStartResultRaw.length > 0 && this.latestStartResultGeneration === this.runtimeGeneration) {
        this.sendRawBridgeMessage(connection, this.latestStartResultRaw)
      }
      connection.on('message', (value: socket.LocalSocketMessageInfo) => {
        try {
          const decoded = decodeSocketChunk(requestBuffer, value.message)
          requestBuffer = decoded.rest
          decoded.messages.forEach((rawMessage: string) => {
            const message = parseVpnBridgeMessage(rawMessage)
            if (message.type === VPN_MESSAGE_RUNTIME_START_REQUEST) {
              this.onRuntimeStartRequest?.(message.data as VpnRuntimeStartRequestData)
            }
          })
        } catch (error) {
          Logger.error(`Failed to process UI runtime request: ${JSON.stringify(error)}`, this.logTarget)
        }
      })
      connection.on('error', (err: Object) => {
        Logger.error(`Connection error: ${JSON.stringify(err)}`, this.logTarget)
        this.dropConnection(connection)
      })
      connection.on('close', () => {
        this.dropConnection(connection)
      })
    })
  }

  close(): void {
    try {
      this.server?.close()
    } catch (error) {
      Logger.error(`VpnServer close error: ${JSON.stringify(error)}`, this.logTarget)
    }
    this.server = undefined
    this.connections.clear()
    this.latestTopologyRaw = ''
    this.latestTrafficRaw = ''
    this.latestStartResultRaw = ''
    this.latestTopologyGeneration = -1
    this.latestTrafficGeneration = -1
    this.latestStartResultGeneration = -1
  }

  beginRuntimeGeneration(): void {
    this.runtimeGeneration++
    this.latestTopologyRaw = ''
    this.latestTrafficRaw = ''
    this.latestStartResultRaw = ''
    this.latestTopologyGeneration = -1
    this.latestTrafficGeneration = -1
    this.latestStartResultGeneration = -1
    this.publishContinuationState(false)
  }

  publishRuntimeStartResult(result: VpnRuntimeStartResultData): void {
    this.latestStartResultRaw = JSON.stringify({
      type: VPN_MESSAGE_RUNTIME_START_RESULT,
      data: result
    } as VpnMessage) + '\n'
    this.latestStartResultGeneration = this.runtimeGeneration
    this.connections.forEach((connection) => {
      this.sendRawBridgeMessage(connection, this.latestStartResultRaw)
    })
  }

  forwardLogs(logs: string[]): void {
    if (logs.length === 0 || this.connections.size === 0) {
      return
    }
    const logData: VpnLogData = { logs: trimForwardLogs(logs) }
    this.broadcast({ type: VPN_MESSAGE_LOGS, data: logData })
  }

  broadcast(msg: VpnMessage): void {
    this.connections.forEach((conn) => {
      this.sendBridgeMessage(conn, msg)
    })
  }

  broadcastRaw(rawMessage: string): void {
    try {
      const message = parseVpnBridgeMessage(rawMessage)
      if (message.type === KERNEL_MESSAGE_RUNTIME_TOPOLOGY) {
        this.latestTopologyRaw = rawMessage
        this.latestTopologyGeneration = this.runtimeGeneration
      } else if (message.type === KERNEL_MESSAGE_TRAFFIC_STATS) {
        this.latestTrafficRaw = rawMessage
        this.latestTrafficGeneration = this.runtimeGeneration
      }
    } catch (error) {
      Logger.error(`Failed to cache bridge snapshot: ${JSON.stringify(error)}`, this.logTarget)
    }
    this.connections.forEach((conn) => {
      this.sendRawBridgeMessage(conn, rawMessage)
    })
  }

  publishContinuationState(active: boolean): void {
    this.continuationActive = active
    this.broadcast({
      type: VPN_MESSAGE_CONTINUE_STATE,
      data: { active } as VpnContinueStateData
    })
  }

  private dropConnection(connection: socket.LocalSocketConnection): void {
    this.connections.delete(connection.clientId)
  }

  private sendBridgeMessage(connection: socket.LocalSocketConnection, msg: VpnMessage): void {
    this.sendRawBridgeMessage(connection, JSON.stringify(msg) + '\n')
  }

  private sendRawBridgeMessage(connection: socket.LocalSocketConnection, rawMessage: string): void {
    const uint8Array = buffer.from(rawMessage).buffer
    connection.send({ data: uint8Array }).catch((err: BusinessError) => {
      this.dropConnection(connection)
      if (err.code === 2301032) {
        Logger.debug(`VpnServer peer disconnected: ${JSON.stringify(err)}`, this.logTarget)
      } else {
        Logger.error(`Failed to send data to UI: ${JSON.stringify(err)}`, this.logTarget)
      }
    })
  }
}
