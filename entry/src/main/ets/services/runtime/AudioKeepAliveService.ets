import { audio } from '@kit.AudioKit'
import { BusinessError } from '@kit.BasicServicesKit'
import { Logger } from '../../shared/logging/Logger'

export class AudioKeepAliveService {
  private static readonly SAMPLE_RATE = 48000
  private static readonly TONE_HZ = 220
  private static readonly TONE_AMPLITUDE = 96
  private static readonly RENDERER_VOLUME = 0.01
  private readonly logTarget: Object | string
  private renderer: audio.AudioRenderer | undefined
  private token: number = 0
  private active: boolean = false
  private phase: number = 0

  private readonly writeDataCallback = (buffer: ArrayBuffer): audio.AudioDataCallbackResult => {
    const samples = new Int16Array(buffer)
    for (let index = 0; index < samples.length; index += 2) {
      const value = Math.round(Math.sin(this.phase) * AudioKeepAliveService.TONE_AMPLITUDE)
      samples[index] = value
      if (index + 1 < samples.length) {
        samples[index + 1] = value
      }
      this.phase += Math.PI * 2 * AudioKeepAliveService.TONE_HZ / AudioKeepAliveService.SAMPLE_RATE
      if (this.phase > Math.PI * 2) {
        this.phase -= Math.PI * 2
      }
    }
    return audio.AudioDataCallbackResult.VALID
  }

  constructor(logTarget: Object | string) {
    this.logTarget = logTarget
  }

  start(): void {
    if (this.renderer || this.active) {
      return
    }
    if (!canIUse('SystemCapability.Multimedia.Audio.Renderer')) {
      Logger.info('Audio renderer capability unavailable, skip audio keep alive', this.logTarget)
      return
    }

    const startToken = ++this.token
    const audioStreamInfo: audio.AudioStreamInfo = {
      samplingRate: audio.AudioSamplingRate.SAMPLE_RATE_48000,
      channels: audio.AudioChannel.CHANNEL_2,
      sampleFormat: audio.AudioSampleFormat.SAMPLE_FORMAT_S16LE,
      encodingType: audio.AudioEncodingType.ENCODING_TYPE_RAW
    }
    const audioRendererInfo: audio.AudioRendererInfo = {
      usage: audio.StreamUsage.STREAM_USAGE_VOICE_ASSISTANT,
      rendererFlags: 0
    }
    const audioRendererOptions: audio.AudioRendererOptions = {
      streamInfo: audioStreamInfo,
      rendererInfo: audioRendererInfo
    }

    audio.createAudioRenderer(audioRendererOptions).then((renderer: audio.AudioRenderer) => {
      if (this.token !== startToken) {
        void renderer.release()
        return
      }
      this.renderer = renderer
      renderer.on('writeData', this.writeDataCallback)
      renderer.setVolume(AudioKeepAliveService.RENDERER_VOLUME).catch((err: BusinessError) => {
        Logger.debug(`audio keep alive set volume ignored: ${err.code}, ${err.message}`, this.logTarget)
      })
      renderer.start().then(() => {
        if (this.token !== startToken) {
          this.stop()
          return
        }
        this.active = true
        Logger.info('audio keep alive started', this.logTarget)
      }).catch((err: BusinessError) => {
        Logger.error(`audio keep alive start failed: ${err.code}, ${err.message}`, this.logTarget)
        this.releaseRenderer(renderer)
      })
    }).catch((err: BusinessError) => {
      Logger.error(`create audio keep alive renderer failed: ${err.code}, ${err.message}`, this.logTarget)
    })
  }

  stop(): void {
    this.token++
    this.active = false
    const renderer = this.renderer
    this.renderer = undefined
    if (!renderer) {
      return
    }
    try {
      renderer.off('writeData', this.writeDataCallback)
    } catch (_) {
    }
    renderer.stop().catch((err: BusinessError) => {
      Logger.debug(`audio keep alive stop ignored: ${err.code}, ${err.message}`, this.logTarget)
    }).finally(() => {
      this.releaseRenderer(renderer)
    })
  }

  private releaseRenderer(renderer: audio.AudioRenderer): void {
    if (this.renderer === renderer) {
      this.renderer = undefined
    }
    this.active = false
    renderer.release().catch((err: BusinessError) => {
      Logger.debug(`audio keep alive release ignored: ${err.code}, ${err.message}`, this.logTarget)
    })
  }
}
