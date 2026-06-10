import { JSON, buffer } from '@kit.ArkTS'
import { KernelSocketMessage, VpnMessage } from './KernelBridgeTypes'

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

export function parseVpnBridgeMessage(rawMessage: string): VpnMessage {
  return JSON.parse(rawMessage) as VpnMessage
}
