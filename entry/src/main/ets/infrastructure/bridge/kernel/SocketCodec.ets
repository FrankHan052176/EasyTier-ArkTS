import { JSON, buffer } from '@kit.ArkTS'
import { KernelSocketMessage, VpnMessage } from './KernelBridgeTypes'

const RUNTIME_SNAPSHOT_PREFIX = '{"messageType":"runtime_snapshot","payloadJson":'

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
