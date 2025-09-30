import Manager from "../../Manager"
import { Config, socks5_proxy } from "../../util/config/ETConfig"

@Extend(TextInput) function fancyText(width: number = 30, length: number = 3) {
  .padding(0)
  .fontSize(16)
  .width(width)
  .maxLength(length)
  .borderRadius(0)
  .type(InputType.Number)
  .backgroundColor(Color.Transparent)
  .selectedBackgroundColor(Color.Transparent)
  .textAlign(TextAlign.Center)
}

const minWidth = 350

@ComponentV2
export struct Socks5 {
  @Param @Require config:Config
  @Local port: string = "1080"

  @Computed
  get comp_width() {
    return Manager.width>=Manager.height*0.625?minWidth:Manager.width-20
  }

  aboutToAppear(): void {
    this.readPort()
  }

  readPort() {
    if (this.config.socks5_proxy !== null) {
      this.port = this.config.socks5_proxy.port
    }
  }

  @Builder
  PortInput() {
    Row() {
      TextInput({text: $$this.port})
        .fancyText(60, 5)
        .onChange(() => {
          this.config.socks5_proxy!.port = this.port
        })
    }
    .animation({
      curve: Curve.Smooth,
      duration: 200,
      expectedFrameRateRange: {
        min: 30,
        max: 120,
        expected: 120
      }
    })
    .borderRadius(13)
    .padding(5)
    .backgroundColor($r("sys.color.interactive_hover"))
    .transition(TransitionEffect.move(TransitionEdge.END))
    .margin({left: 5})
  }

  build() {
    Row() {
      Text("Socks5服务器")
        .fontSize(17)
        .fontColor($r("sys.color.font_primary"))
      Row() {
        Button('启用', {
          type: ButtonType.Normal,
          buttonStyle: this.config.socks5_proxy !== null?ButtonStyleMode.EMPHASIZED:ButtonStyleMode.NORMAL,
          role: ButtonRole.NORMAL
        })
          .height(34)
          .borderRadius(13)
          .fontSize(16)
          .clickEffect({
            level: ClickEffectLevel.LIGHT,
            scale: 0.9
          })
          .onClick(() => {
            animateToImmediately({
              curve: Curve.LinearOutSlowIn,
              duration: 300,
              expectedFrameRateRange: {
                min: 30,
                max: 120,
                expected: 120
              }
            }, () => {
              if (this.config.socks5_proxy !== null) {
                this.config.socks5_proxy = null
              }else {
                this.config.initSocks5()
                this.readPort()
              }
            })
          })
        if (this.config.socks5_proxy !== null) {
          this.PortInput()
        }
      }
    }
    .width(this.comp_width)
    .padding({left: 15, top: 6, bottom: 6, right: 6})
    .borderRadius(18)
    .backgroundColor($r("sys.color.comp_background_primary"))
    .alignItems(VerticalAlign.Center)
    .justifyContent(FlexAlign.SpaceBetween)
    .clip(true)
  }
}