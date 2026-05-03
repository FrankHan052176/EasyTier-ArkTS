import { JSON, buffer } from '@kit.ArkTS'
import { KernelSocketMessage, VpnMessage } from './KernelBridgeTypes'

export interface SocketDrainResult {
  messages: string[]
  rest: string
}

export function decodeSocketChunk(currentBuffer: string, message: ArrayBuffer | Uint8Array | string): SocketDrainResult {
  const chunkText = typeof message === 'string' ? message : buffer.from(message).toString()
  const parts = (currentBuffer + chunkText).split('\n')
  const messages: string[] = []
  for (let i = 0; i < parts.length - 1; i++) {
    if (parts[i].length > 0) {
      messages.push(parts[i])
    }
  }
  return {
    messages,
    rest: parts[parts.length - 1] ?? ''
  }
}

export function parseKernelSocketMessage(rawMessage: string): KernelSocketMessage {
  return JSON.parse(rawMessage) as KernelSocketMessage
}

export function parseVpnBridgeMessage(rawMessage: string): VpnMessage {
  return JSON.parse(rawMessage) as VpnMessage
}
