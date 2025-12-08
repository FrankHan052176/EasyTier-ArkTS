import { Sfp2vp } from '../../AppManager'

@ComponentV2
export struct TertiaryButton {
  @Param @Require text: ResourceStr
  @Param @Require fontSize: number
  @Param fontColor: ResourceColor = $r("sys.color.font_tertiary")

  @Computed
  get TextHeight() {
    return Sfp2vp(this.fontSize)
  }

  build() {
    Text(this.text)
      .textAlign(TextAlign.Center)
      .fontColor(this.fontColor)
      .backgroundColor($r("sys.color.comp_background_tertiary"))
      .fontSize(this.fontSize)
      .borderRadius(this.TextHeight / 2 + 3)
      .padding({
        left: this.TextHeight / 2 + 3,
        right: this.TextHeight / 2 + 3,
        top: this.TextHeight / 2 + 1,
        bottom: this.TextHeight / 2 + 1
      })
  }
}

@ComponentV2
export struct PrimaryButton {
  @Param @Require text: ResourceStr
  @Param @Require fontSize: number
  @Param fontColor: ResourceColor = $r("sys.color.font_primary")

  build() {
    Text(this.text)
      .textAlign(TextAlign.Center)
      .fontColor(this.fontColor)
      .backgroundColor(Color.Transparent)
      .fontSize(this.fontSize)
  }
}