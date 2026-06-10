export interface EditPageParam {
  uuid: string,
  unsafe: boolean,
  source?: string,
  remoteSessionId?: string,
  remoteDeviceName?: string
}

export interface RemoteSettingPageParam {
  category: string
  title: string
  remoteSessionId?: string
  remoteDeviceName?: string
}

export interface RemoteStatusPageParam {
  configId: string
  title: string
  remoteSessionId?: string
  remoteDeviceName?: string
}
