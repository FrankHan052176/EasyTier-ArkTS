import {
  BACKGROUND_KEEP_ALIVE_AUDIO_PLAYBACK,
  BACKGROUND_KEEP_ALIVE_DATA_TRANSFER,
  normalizeBackgroundKeepAliveMode
} from './BackgroundKeepAliveTypes'

export const RUNTIME_MODE_DATA_TRANSFER = BACKGROUND_KEEP_ALIVE_DATA_TRANSFER
export const RUNTIME_MODE_AUDIO_PLAYBACK = BACKGROUND_KEEP_ALIVE_AUDIO_PLAYBACK
export const RUNTIME_MODE_SUBPROCESS = 'subprocess'

export type RuntimeMode = 'dataTransfer' | 'audioPlayback' | 'subprocess'

export interface RuntimeModeSelectOption {
  value: string
  label: string
}

export function runtimeModeFromSettings(extMode: boolean, backgroundKeepAliveMode: string | undefined): RuntimeMode {
  if (extMode) {
    return RUNTIME_MODE_SUBPROCESS
  }
  return normalizeBackgroundKeepAliveMode(backgroundKeepAliveMode)
}

export function normalizeRuntimeMode(value: string | undefined): RuntimeMode {
  if (value === RUNTIME_MODE_SUBPROCESS) {
    return RUNTIME_MODE_SUBPROCESS
  }
  return normalizeBackgroundKeepAliveMode(value)
}

export function runtimeModeText(value: string | undefined): string {
  switch (normalizeRuntimeMode(value)) {
    case RUNTIME_MODE_SUBPROCESS:
      return '子进程模式'
    case RUNTIME_MODE_AUDIO_PLAYBACK:
      return '音频保活'
    default:
      return '数据传输保活'
  }
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
    },
    {
      value: RUNTIME_MODE_SUBPROCESS,
      label: runtimeModeText(RUNTIME_MODE_SUBPROCESS)
    }
  ]
}
