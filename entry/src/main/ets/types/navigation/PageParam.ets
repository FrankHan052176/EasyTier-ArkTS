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

export interface RemoteStatusParam {
  source: string
  configId: string
  title: string
  remoteSessionId?: string
  remoteDeviceName?: string
}
