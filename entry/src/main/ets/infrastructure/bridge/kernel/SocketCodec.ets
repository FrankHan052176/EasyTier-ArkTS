import { JSON, buffer } from '@kit.ArkTS'
import { KernelSocketMessage, VpnMessage } from './KernelBridgeTypes'

const RUNTIME_SNAPSHOT_PREFIX = '{"messageType":"runtime_snapshot","payloadJson":'
const MAX_SOCKET_REST_LENGTH = 4 * 1024 * 1024

export interface SocketDrainResult {
  messages: string[]
  rest: string
}

export function decodeSocketChunk(currentBuffer: string, message: ArrayBuffer | Uint8Array | string): SocketDrainResult {
  const chunkText = typeof message === 'string' ? message : buffer.from(message).toString()
  const combined = (currentBuffer.length > MAX_SOCKET_REST_LENGTH ? '' : currentBuffer) + chunkText
  const messages: string[] = []
  let start = 0
  while (start < combined.length) {
    const newlineIndex = combined.indexOf('\n', start)
    if (newlineIndex < 0) {
      break
    }
    if (newlineIndex > start) {
      messages.push(combined.substring(start, newlineIndex))
    }
    start = newlineIndex + 1
  }
  const rest = combined.substring(start)
  return {
    messages,
    rest: rest.length > MAX_SOCKET_REST_LENGTH ? '' : rest
  }
}

export function parseKernelSocketMessage(rawMessage: string): KernelSocketMessage {
  return JSON.parse(rawMessage) as KernelSocketMessage
}

export function isRuntimeSnapshotMessage(rawMessage: string): boolean {
  return rawMessage.startsWith(RUNTIME_SNAPSHOT_PREFIX)
}

export function buildVpnRuntimeSnapshotMessage(rawMessage: string): string {
  if (rawMessage.startsWith(RUNTIME_SNAPSHOT_PREFIX) && rawMessage.endsWith('}')) {
    const payloadStart = RUNTIME_SNAPSHOT_PREFIX.length
    if (rawMessage[payloadStart] !== '"') {
      const payloadJson = rawMessage.substring(payloadStart, rawMessage.length - 1)
      return `{"type":"runtime_snapshot","data":${payloadJson}}\n`
    }
  }
  const msg = parseKernelSocketMessage(rawMessage)
  const payloadJson = typeof msg.payloadJson === 'string' ? msg.payloadJson : JSON.stringify(msg.payloadJson)
  return `{"type":"runtime_snapshot","data":${payloadJson}}\n`
}

export function parseVpnBridgeMessage(rawMessage: string): VpnMessage {
  return JSON.parse(rawMessage) as VpnMessage
}
