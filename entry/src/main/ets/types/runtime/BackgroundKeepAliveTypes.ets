export const BACKGROUND_KEEP_ALIVE_DATA_TRANSFER = 'dataTransfer'
export const BACKGROUND_KEEP_ALIVE_AUDIO_PLAYBACK = 'audioPlayback'
export const BACKGROUND_KEEP_ALIVE_TASK_KEEPING = 'taskKeeping'

export type BackgroundKeepAliveMode = 'dataTransfer' | 'audioPlayback' | 'taskKeeping'

export function normalizeBackgroundKeepAliveMode(value: string | undefined): BackgroundKeepAliveMode {
  if (value === BACKGROUND_KEEP_ALIVE_AUDIO_PLAYBACK) {
    return BACKGROUND_KEEP_ALIVE_AUDIO_PLAYBACK
  }
  if (value === BACKGROUND_KEEP_ALIVE_TASK_KEEPING) {
    return BACKGROUND_KEEP_ALIVE_TASK_KEEPING
  }
  return BACKGROUND_KEEP_ALIVE_DATA_TRANSFER
}

export function backgroundKeepAliveModeText(value: string | undefined): string {
  const mode = normalizeBackgroundKeepAliveMode(value)
  if (mode === BACKGROUND_KEEP_ALIVE_AUDIO_PLAYBACK) {
    return '音频播放'
  }
  if (mode === BACKGROUND_KEEP_ALIVE_TASK_KEEPING) {
    return '计算任务'
  }
  return '数据传输'
}
