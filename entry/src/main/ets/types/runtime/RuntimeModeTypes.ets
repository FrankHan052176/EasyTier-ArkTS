import {
  BACKGROUND_KEEP_ALIVE_AUDIO_PLAYBACK,
  BACKGROUND_KEEP_ALIVE_DATA_TRANSFER,
  BACKGROUND_KEEP_ALIVE_TASK_KEEPING,
  normalizeBackgroundKeepAliveMode
} from './BackgroundKeepAliveTypes'

export const RUNTIME_MODE_DATA_TRANSFER = BACKGROUND_KEEP_ALIVE_DATA_TRANSFER
export const RUNTIME_MODE_AUDIO_PLAYBACK = BACKGROUND_KEEP_ALIVE_AUDIO_PLAYBACK
export const RUNTIME_MODE_TASK_KEEPING = BACKGROUND_KEEP_ALIVE_TASK_KEEPING
export const RUNTIME_MODE_SUBPROCESS = 'subprocess'

export type RuntimeMode = 'dataTransfer' | 'audioPlayback' | 'taskKeeping' | 'subprocess'

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
  const mode = normalizeRuntimeMode(value)
  if (mode === RUNTIME_MODE_SUBPROCESS) {
    return '子进程模式'
  }
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
    },
    {
      value: RUNTIME_MODE_SUBPROCESS,
      label: runtimeModeText(RUNTIME_MODE_SUBPROCESS)
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
