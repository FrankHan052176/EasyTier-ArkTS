import { JSON } from '@kit.ArkTS'
import {
  REMOTE_MANAGE_PROTOCOL_VERSION,
  REMOTE_MANAGE_SERVICE_NAME,
  RemoteWireFrame
} from './RemoteWireTypes'

export const REMOTE_SEND_MESSAGE_MAX_BYTES = 1024
const REMOTE_FRAME_MAX_BYTES = 900
const REMOTE_MAX_PACKET_CHUNKS = 2048
const REMOTE_INCOMING_MAX_PACKETS = 8
const REMOTE_INCOMING_PACKET_TTL_MS = 15000

export interface RemoteIncomingPacket {
  total: number
  chunks: string[]
  received: number
  createdAt: number
}

export function utf8ByteLength(text: string): number {
  let bytes = 0
  for (let index = 0; index < text.length; index++) {
    const code = text.charCodeAt(index)
    if (code < 0x80) {
      bytes += 1
    } else if (code < 0x800) {
      bytes += 2
    } else if (code >= 0xD800 && code <= 0xDBFF && index + 1 < text.length) {
      const next = text.charCodeAt(index + 1)
      if (next >= 0xDC00 && next <= 0xDFFF) {
        bytes += 4
        index += 1
      } else {
        bytes += 3
      }
    } else {
      bytes += 3
    }
  }
  return bytes
}

function previousCodePointEnd(text: string, start: number, end: number): number {
  if (end <= start) {
    return start
  }
  let nextEnd = end - 1
  const code = text.charCodeAt(nextEnd)
  if (code >= 0xDC00 && code <= 0xDFFF && nextEnd > start) {
    nextEnd -= 1
  } else if (code >= 0xD800 && code <= 0xDBFF && end < text.length) {
    const next = text.charCodeAt(end)
    if (next >= 0xDC00 && next <= 0xDFFF) {
      nextEnd -= 1
    }
  }
  return Math.max(start, nextEnd)
}

function buildFrame(packetId: string, part: number, total: number, data: string): RemoteWireFrame {
  return {
    v: REMOTE_MANAGE_PROTOCOL_VERSION,
    service: REMOTE_MANAGE_SERVICE_NAME,
    packetId,
    part,
    total,
    data
  }
}

function takeFrameChunk(raw: string, offset: number, packetId: string, part: number): string {
  let end = Math.min(raw.length, offset + 256)
  if (end <= offset) {
    return ''
  }
  let chunk = raw.substring(offset, end)
  while (chunk.length > 0 &&
    utf8ByteLength(JSON.stringify(buildFrame(packetId, part, 999999, chunk))) > REMOTE_FRAME_MAX_BYTES) {
    end = previousCodePointEnd(raw, offset, end)
    chunk = raw.substring(offset, end)
  }
  if (chunk.length === 0) {
    throw new Error('远端消息分片失败')
  }
  return chunk
}

function splitPacket(raw: string, packetId: string): string[] {
  const chunks: string[] = []
  let offset = 0
  while (offset < raw.length) {
    const chunk = takeFrameChunk(raw, offset, packetId, chunks.length)
    chunks.push(chunk)
    if (chunks.length > REMOTE_MAX_PACKET_CHUNKS) {
      throw new Error('远端消息过大')
    }
    offset += chunk.length
  }
  if (chunks.length === 0) {
    chunks.push('')
  }
  return chunks
}

export function buildRemoteWireFrames(raw: string, packetId: string): RemoteWireFrame[] {
  const chunks = splitPacket(raw, packetId)
  const total = chunks.length
  return chunks.map((chunk, part) => buildFrame(packetId, part, total, chunk))
}

export function isRemoteWireFrameValid(frame: RemoteWireFrame): boolean {
  return frame.service === REMOTE_MANAGE_SERVICE_NAME &&
    frame.v === REMOTE_MANAGE_PROTOCOL_VERSION &&
    frame.total > 0 &&
    frame.total <= REMOTE_MAX_PACKET_CHUNKS &&
    frame.part >= 0 &&
    frame.part < frame.total
}

export function pruneRemoteIncomingPackets(incoming: Map<string, RemoteIncomingPacket>): void {
  const now = Date.now()
  incoming.forEach((packet, packetId) => {
    if (now - packet.createdAt > REMOTE_INCOMING_PACKET_TTL_MS) {
      incoming.delete(packetId)
    }
  })
  while (incoming.size > REMOTE_INCOMING_MAX_PACKETS) {
    const first = incoming.keys().next()
    if (first.done) {
      return
    }
    incoming.delete(first.value)
  }
}

export function reassembleRemoteFrame(
  incomingPackets: Map<string, RemoteIncomingPacket>,
  frame: RemoteWireFrame
): string | undefined {
  if (frame.total === 1) {
    return frame.data
  }
  pruneRemoteIncomingPackets(incomingPackets)
  let incoming = incomingPackets.get(frame.packetId)
  if (incoming && incoming.total !== frame.total) {
    incomingPackets.delete(frame.packetId)
    return undefined
  }
  if (!incoming) {
    if (incomingPackets.size >= REMOTE_INCOMING_MAX_PACKETS) {
      pruneRemoteIncomingPackets(incomingPackets)
    }
    incoming = {
      total: frame.total,
      chunks: new Array<string>(frame.total),
      received: 0,
      createdAt: Date.now()
    }
    incomingPackets.set(frame.packetId, incoming)
  }
  if (incoming.chunks[frame.part] === undefined) {
    incoming.chunks[frame.part] = frame.data
    incoming.received += 1
  }
  if (incoming.received < incoming.total) {
    return undefined
  }
  incomingPackets.delete(frame.packetId)
  return incoming.chunks.join('')
}
