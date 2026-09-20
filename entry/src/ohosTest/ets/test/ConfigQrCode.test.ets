import { describe, it, expect } from '@ohos/hypium'
import { abilityDelegatorRegistry } from '@kit.TestKit'
import { fileIo, fileUri } from '@kit.CoreFileKit'
import { image } from '@kit.ImageKit'
import { detectBarcode, scanCore } from '@kit.ScanKit'
import { ConfigQrCodeError, ConfigQrCodeService, configQrErrorMessage } from '../../../main/ets/services/share/ConfigQrCodeService'

async function assertQrRoundtrip(content: string): Promise<void> {
  const pixelMap = await ConfigQrCodeService.create(content)
  const packer = image.createImagePacker()
  const context = abilityDelegatorRegistry.getAbilityDelegator().getAppContext()
  const path = `${context.cacheDir}/config-qr-regression-${Date.now()}.png`
  try {
    const packed = await packer.packing(pixelMap, { format: 'image/png', quality: 100 })
    const file = fileIo.openSync(path, fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC)
    try {
      fileIo.writeSync(file.fd, packed)
    } finally {
      fileIo.closeSync(file)
    }
    const results = await detectBarcode.decode({ uri: fileUri.getUriFromPath(path) }, {
      scanTypes: [scanCore.ScanType.QR_CODE], enableMultiMode: false, enableAlbum: false
    })
    expect(results.length).assertEqual(1)
    // Compare as a boolean so test failure reports never print share contents.
    expect(results[0].originalValue === content).assertTrue()
  } finally {
    await pixelMap.release()
    await packer.release()
    try {
      fileIo.unlinkSync(path)
    } catch (_) {}
  }
}

export default function configQrCodeTest() {
  describe('ConfigQrCode', () => {
    it('roundtripsCompleteShareUrlsBeyondStringAndDefaultCorrectionLimits', 0, async () => {
      const prefix = 'https://easytier.cn/comp_cfg?name=%E6%B5%8B%E8%AF%95&only_start=true&cfg='
      for (const length of [512, 513, 1025, 2048]) {
        const content = prefix + 'aZ09_-'.repeat(350).slice(0, length - prefix.length)
        await assertQrRoundtrip(content)
      }
    })

    it('rejectsEmptyAndOversizeUtf8WithoutLeakingContent', 0, async () => {
      for (const content of ['', 'x'.repeat(2049), '汉'.repeat(683)]) {
        let rejected = false
        try {
          const pixelMap = await ConfigQrCodeService.create(content)
          await pixelMap.release()
        } catch (error) {
          rejected = error instanceof ConfigQrCodeError
          const message = configQrErrorMessage(error as Error)
          expect(message).assertContain(content.length === 0 ? '分享链接生成失败' : '配置过大')
          if (content.length > 0) {
            expect(message.includes(content)).assertFalse()
          }
        }
        expect(rejected).assertTrue()
      }
      expect(configQrErrorMessage(new Error('private-url-marker')).includes('private-url-marker')).assertFalse()
    })

    it('acceptsExactly2048Utf8Bytes', 0, async () => {
      const pixelMap = await ConfigQrCodeService.create('汉'.repeat(682) + 'ab')
      await pixelMap.release()
    })
  })
}
