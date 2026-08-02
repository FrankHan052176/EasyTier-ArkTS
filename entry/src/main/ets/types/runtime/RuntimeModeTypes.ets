import {
  BACKGROUND_KEEP_ALIVE_AUDIO_PLAYBACK,
  BACKGROUND_KEEP_ALIVE_DATA_TRANSFER,
  BACKGROUND_KEEP_ALIVE_TASK_KEEPING,
  normalizeBackgroundKeepAliveMode
} from './BackgroundKeepAliveTypes'

export const RUNTIME_MODE_DATA_TRANSFER = BACKGROUND_KEEP_ALIVE_DATA_TRANSFER
export const RUNTIME_MODE_AUDIO_PLAYBACK = BACKGROUND_KEEP_ALIVE_AUDIO_PLAYBACK
export const RUNTIME_MODE_TASK_KEEPING = BACKGROUND_KEEP_ALIVE_TASK_KEEPING

export type RuntimeMode = 'dataTransfer' | 'audioPlayback' | 'taskKeeping'

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
  const mode = normalizeRuntimeMode(value)
  if (mode === RUNTIME_MODE_AUDIO_PLAYBACK) {
    return '音乐保活'
  }
  if (mode === RUNTIME_MODE_TASK_KEEPING) {
    return '计算任务保活'
  }
  return '数据传输保活'
}

export function runtimeModeOptions(includeTaskKeeping: boolean = false): RuntimeModeSelectOption[] {
  const options: RuntimeModeSelectOption[] = [
    {
      value: RUNTIME_MODE_DATA_TRANSFER,
      label: runtimeModeText(RUNTIME_MODE_DATA_TRANSFER)
    },
    {
      value: RUNTIME_MODE_AUDIO_PLAYBACK,
      label: runtimeModeText(RUNTIME_MODE_AUDIO_PLAYBACK)
    }
  ]
  if (includeTaskKeeping) {
    options.push({
      value: RUNTIME_MODE_TASK_KEEPING,
      label: runtimeModeText(RUNTIME_MODE_TASK_KEEPING)
    })
  }
  return options
}
