import { WindowUtil } from '../../WindowUtil'

@CustomDialog
export struct EasyTierProRecommendationDialog {
  controller?: CustomDialogController
  onOpen: () => void = () => {}
  onDismiss: () => void = () => {}

  private dialogWidth(): number {
    return Math.min(400, Math.max(296, WindowUtil.minSide() - 48))
  }

  build(): void {
    Column({ space: 16 }) {
      Row({ space: 12 }) {
        SymbolGlyph($r('sys.symbol.cloud'))
          .fontSize(28)
          .fontColor([$r('sys.color.brand')])

        Column({ space: 2 }) {
          Text($r('app.string.easytier_pro_recommendation_title'))
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('sys.color.font_primary'))
          Text($r('app.string.easytier_pro_recommendation_subtitle'))
            .fontSize(13)
            .fontColor($r('sys.color.font_secondary'))
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')

      Text($r('app.string.easytier_pro_recommendation_body'))
        .width('100%')
        .fontSize(15)
        .fontColor($r('sys.color.font_secondary'))
        .lineHeight(22)

      Column({ space: 8 }) {
        Image($r('app.media.easytier_pro_qr'))
          .width(168)
          .height(168)
          .objectFit(ImageFit.Contain)
          .accessibilityText($r('app.string.easytier_pro_qr_accessibility'))

        Text($r('app.string.easytier_pro_qr_hint'))
          .fontSize(12)
          .fontColor($r('sys.color.font_tertiary'))
      }
      .width('100%')
      .padding({ top: 12, bottom: 12 })
      .backgroundColor($r('sys.color.comp_background_tertiary'))
      .borderRadius(16)

      Button($r('app.string.easytier_pro_open_appgallery'), {
        type: ButtonType.Capsule,
        buttonStyle: ButtonStyleMode.EMPHASIZED,
        role: ButtonRole.NORMAL
      })
        .width('100%')
        .onClick(() => this.onOpen())

      Button($r('app.string.easytier_pro_later'), {
        type: ButtonType.Capsule,
        buttonStyle: ButtonStyleMode.NORMAL,
        role: ButtonRole.NORMAL
      })
        .width('100%')
        .onClick(() => this.onDismiss())
    }
    .width(this.dialogWidth())
    .padding(24)
    .borderRadius(24)
    .backgroundColor($r('sys.color.comp_background_primary'))
  }
}
