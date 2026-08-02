import {
  BACKGROUND_KEEP_ALIVE_AUDIO_PLAYBACK,
  BACKGROUND_KEEP_ALIVE_DATA_TRANSFER,
  normalizeBackgroundKeepAliveMode
} from './BackgroundKeepAliveTypes'

export const RUNTIME_MODE_DATA_TRANSFER = BACKGROUND_KEEP_ALIVE_DATA_TRANSFER
export const RUNTIME_MODE_AUDIO_PLAYBACK = BACKGROUND_KEEP_ALIVE_AUDIO_PLAYBACK

export type RuntimeMode = 'dataTransfer' | 'audioPlayback'

export interface RuntimeModeSelectOption {
  value: string
  label: string
}

export function runtimeModeFromSettings(backgroundKeepAliveMode: string | undefined): RuntimeMode {
  return normalizeBackgroundKeepAliveMode(backgroundKeepAliveMode)
}

export function normalizeRuntimeMode(value: string | undefined): RuntimeMode {
  return normalizeBackgroundKeepAliveMode(value)
}

export function runtimeModeText(value: string | undefined): string {
  return normalizeRuntimeMode(value) === RUNTIME_MODE_AUDIO_PLAYBACK ? '音乐保活' : '数据传输保活'
}

export function runtimeModeOptions(): RuntimeModeSelectOption[] {
  return [
    {
      value: RUNTIME_MODE_DATA_TRANSFER,
      label: runtimeModeText(RUNTIME_MODE_DATA_TRANSFER)
    },
    {
      value: RUNTIME_MODE_AUDIO_PLAYBACK,
      label: runtimeModeText(RUNTIME_MODE_AUDIO_PLAYBACK)
    }
  ]
}
