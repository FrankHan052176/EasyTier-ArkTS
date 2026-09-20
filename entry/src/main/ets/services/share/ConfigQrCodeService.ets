import { util } from '@kit.ArkTS'
import { BusinessError } from '@kit.BasicServicesKit'
import { image } from '@kit.ImageKit'
import { generateBarcode, scanCore } from '@kit.ScanKit'
import { Logger } from '../../shared/logging/Logger'

// Scan Kit's string overload rejects >512 characters. The API 12+ byte overload
// supports up to 2048 bytes at LEVEL_M. Keep the complete standard share URL.
const MAX_QR_CONTENT_BYTES = 2048

export class ConfigQrCodeError extends Error {
  constructor(message: string) {
    super(message)
    this.name = 'ConfigQrCodeError'
  }
}

export class ConfigQrCodeService {
  static async create(content: string): Promise<image.PixelMap> {
    if (content.length === 0) {
      throw new ConfigQrCodeError('分享链接生成失败，请重试')
    }
    const bytes = util.TextEncoder.create('utf-8').encodeInto(content)
    if (bytes.byteLength > MAX_QR_CONTENT_BYTES) {
      Logger.warn(`QR content exceeds capacity: bytes=${bytes.byteLength}`, 'ConfigQrCodeService')
      throw new ConfigQrCodeError('配置过大，无法生成二维码，请使用分享直达链接或 Toml 文件')
    }
    // Use an exact-sized ArrayBuffer, not a possibly larger backing buffer.
    const contentBuffer = new ArrayBuffer(bytes.byteLength)
    new Uint8Array(contentBuffer).set(bytes)
    const options: generateBarcode.CreateOptions = {
      scanType: scanCore.ScanType.QR_CODE,
      width: 800,
      height: 800,
      level: generateBarcode.ErrorCorrectionLevel.LEVEL_M
    }
    try {
      return await generateBarcode.createBarcode(contentBuffer, options)
    } catch (error) {
      // URLs contain credentials. Never log the payload or native error message.
      const code = (error as BusinessError).code
      Logger.error(`QR encoding failed: code=${code}, bytes=${bytes.byteLength}`, 'ConfigQrCodeService')
      throw new ConfigQrCodeError('二维码生成失败，请重试或使用分享直达链接')
    }
  }
}

export function configQrErrorMessage(error: Error): string {
  return error instanceof ConfigQrCodeError ? error.message : '二维码生成失败，请重试'
}
