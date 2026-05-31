import { image } from '@kit.ImageKit'
import { WindowUtil } from '../../WindowUtil'

@Builder
export function QRImage(img: image.PixelMap) {
  Image(img).size({ width: WindowUtil.minSide() * 0.7, height: WindowUtil.minSide() * 0.7 })
    .margin(8)
}
