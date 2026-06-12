export const BACKGROUND_KEEP_ALIVE_DATA_TRANSFER = 'dataTransfer'
export const BACKGROUND_KEEP_ALIVE_AUDIO_PLAYBACK = 'audioPlayback'

export type BackgroundKeepAliveMode = 'dataTransfer' | 'audioPlayback'

export function normalizeBackgroundKeepAliveMode(value: string | undefined): BackgroundKeepAliveMode {
  return value === BACKGROUND_KEEP_ALIVE_AUDIO_PLAYBACK ? BACKGROUND_KEEP_ALIVE_AUDIO_PLAYBACK :
    BACKGROUND_KEEP_ALIVE_DATA_TRANSFER
}

export function backgroundKeepAliveModeText(value: string | undefined): string {
  return normalizeBackgroundKeepAliveMode(value) === BACKGROUND_KEEP_ALIVE_AUDIO_PLAYBACK ? '音频播放' : '数据传输'
}
