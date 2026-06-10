import { image } from '@kit.ImageKit'
import { WindowUtil } from '../../WindowUtil'

@Builder
export function QRImage(img: image.PixelMap) {
  Image(img).size({ width: WindowUtil.minSide() * 0.7, height: WindowUtil.minSide() * 0.7 })
    .margin(8)
}

@CustomDialog
export struct QRDialog {
  controller?: CustomDialogController
  pixelMap?: image.PixelMap

  build() {
    Column() {
      if (this.pixelMap) {
        QRImage(this.pixelMap)
      }
    }
    .borderRadius(18)
    .backgroundColor($r('sys.color.comp_background_primary'))
    .padding(12)
  }
}
