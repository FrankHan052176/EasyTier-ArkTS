import Manager from "../../Manager"
import { Config } from "../../util/config/ETConfig"

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
export struct IPv4 {
  @Param @Require config:Config
  @Local ip1: string = "10"
  @Local ip2: string = "0"
  @Local ip3: string = "0"
  @Local ip4: string = "1"
  @Local Mask: string = "24"
  @Computed
  get comp_width() {
    return Manager.width>=Manager.height*0.625?minWidth:Manager.width-20
  }

  aboutToAppear(): void {
    let split = this.config.dhcp.ipv4.split(".")
    this.ip1 = split[0]
    this.ip2 = split[1]
    this.ip3 = split[2]
    this.ip4 = split[3]
  }

  @Builder
  IPInput() {
    Row() {
      TextInput({text: $$this.ip1})
        .fancyText()
        .onChange(() => {
          this.config.dhcp.ipv4 = this.ip1+"."+this.ip2+"."+this.ip3+"."+this.ip4
        })
      Text(".")
        .backgroundColor(Color.Transparent)
      TextInput({text: $$this.ip2})
        .fancyText()
        .onChange(() => {
          this.config.dhcp.ipv4 = this.ip1+"."+this.ip2+"."+this.ip3+"."+this.ip4
        })
      Text(".")
        .backgroundColor(Color.Transparent)
      TextInput({text: $$this.ip3})
        .fancyText()
        .onChange(() => {
          this.config.dhcp.ipv4 = this.ip1+"."+this.ip2+"."+this.ip3+"."+this.ip4
        })
      Text(".")
        .backgroundColor(Color.Transparent)
      TextInput({text: $$this.ip4})
        .fancyText()
        .onChange(() => {
          this.config.dhcp.ipv4 = this.ip1+"."+this.ip2+"."+this.ip3+"."+this.ip4
        })
      Text("/")
        .backgroundColor(Color.Transparent)
      TextInput({text: $$this.Mask})
        .fancyText(24, 2)
        .onChange(() => {
          this.config.dhcp.mask = Number.parseInt(this.Mask)
        })
    }
    .width(177)
    .animation({
      curve: Curve.Smooth,
      duration: 200,
      expectedFrameRateRange: {
        min: 30,
        max: 120,
        expected: 120
      }
    })
    .margin({left: 5})
    .borderRadius(13)
    .padding(5)
    .backgroundColor($r("sys.color.interactive_hover"))
    .transition(TransitionEffect.move(TransitionEdge.END))
  }

  build() {
    Row() {
      Text("IPv4")
        .fontSize(17)
        .fontColor($r("sys.color.font_primary"))
      Row() {
        Button('DHCP', {
          type: ButtonType.Normal,
          buttonStyle: this.config.dhcp.enable?ButtonStyleMode.EMPHASIZED:ButtonStyleMode.NORMAL,
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
              this.config.dhcp.enable = !this.config.dhcp.enable
            })
          })
        if (!this.config.dhcp.enable) {
          this.IPInput()
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