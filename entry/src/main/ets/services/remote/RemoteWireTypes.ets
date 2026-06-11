export const REMOTE_MANAGE_SERVICE_NAME = 'easytier.remote.manage.v1'
export const REMOTE_MANAGE_PROTOCOL_VERSION = 1

export interface RemoteRpcRequest {
  id: string
  op: string
  payloadJson?: string
}

export interface RemoteRpcResponse {
  id: string
  ok: boolean
  payloadJson?: string
  error?: string
}

export interface RemoteRpcNotify {
  event: string
  payloadJson?: string
}

export interface RemoteWireFrame {
  v: number
  service: string
  packetId: string
  part: number
  total: number
  data: string
}

export class RemoteConnectParameters {
  protocol: string = ''
  version: string = ''
}
