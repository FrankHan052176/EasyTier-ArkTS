import Manager from "../../Manager"
import { Config } from "../../util/config/ETConfig"

@Extend(TextInput) function fancyText(enable: boolean, weight: number = 30, length: number = 3) {
  .fontColor(enable?$r("sys.color.font_secondary"):$r("sys.color.font_primary"))
  .fontSize(16)
  .layoutWeight(weight)
  .maxLength(length)
  .borderRadius(0)
  .type(InputType.Number)
  .backgroundColor(Color.Transparent)
  .selectedBackgroundColor(Color.Transparent)
  .textAlign(TextAlign.Start)
  .padding({left: 5, right: 0, top: 0, bottom: 0})
}

@ComponentV2
export struct IPv4 {
  @Param @Require config:Config
  @Param @Require comp_width: number
  @Local ip1: string = "10"
  @Local ip2: string = "0"
  @Local ip3: string = "0"
  @Local ip4: string = "1"
  @Local Mask: string = "24"

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
        .fancyText(this.config.dhcp.enable)
        .onChange(() => {
          this.config.dhcp.ipv4 = this.ip1+"."+this.ip2+"."+this.ip3+"."+this.ip4
        })
      Text(".")
        .fontColor(this.config.dhcp.enable?$r("sys.color.font_secondary"):$r("sys.color.font_primary"))
        .backgroundColor(Color.Transparent)
      TextInput({text: $$this.ip2})
        .fancyText(this.config.dhcp.enable)
        .onChange(() => {
          this.config.dhcp.ipv4 = this.ip1+"."+this.ip2+"."+this.ip3+"."+this.ip4
        })
      Text(".")
        .fontColor(this.config.dhcp.enable?$r("sys.color.font_secondary"):$r("sys.color.font_primary"))
        .backgroundColor(Color.Transparent)
      TextInput({text: $$this.ip3})
        .fancyText(this.config.dhcp.enable)
        .onChange(() => {
          this.config.dhcp.ipv4 = this.ip1+"."+this.ip2+"."+this.ip3+"."+this.ip4
        })
      Text(".")
        .fontColor(this.config.dhcp.enable?$r("sys.color.font_secondary"):$r("sys.color.font_primary"))
        .backgroundColor(Color.Transparent)
      TextInput({text: $$this.ip4})
        .fancyText(this.config.dhcp.enable)
        .onChange(() => {
          this.config.dhcp.ipv4 = this.ip1+"."+this.ip2+"."+this.ip3+"."+this.ip4
        })
      Text("/")
        .fontColor(this.config.dhcp.enable?$r("sys.color.font_secondary"):$r("sys.color.font_primary"))
        .backgroundColor(Color.Transparent)
      TextInput({text: $$this.Mask})
        .fancyText(this.config.dhcp.enable, 24, 2)
        .onChange(() => {
          this.config.dhcp.mask = Number.parseInt(this.Mask)
        })
    }
    .enabled(!this.config.dhcp.enable)
    .width("100%")
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
  }

  build() {
    Column() {
      Row() {
        Text($r("app.string.virtual_ipv4"))
          .fontSize(17)
          .fontColor($r("sys.color.font_primary"))
        Row() {
          Button($r("app.string.virtual_ipv4_dhcp"), {
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
        }
      }
      .padding({left: 5})
      .alignItems(VerticalAlign.Center)
      .width('100%')
      .justifyContent(FlexAlign.SpaceBetween)
      Row() {
        this.IPInput()
      }
      .margin({top: 5})
      .width('100%')
      .justifyContent(FlexAlign.Center)
    }
    .width(this.comp_width)
    .padding({top: 10, left: 10, bottom: 10, right: 10})
    .borderRadius(18)
    .backgroundColor($r("sys.color.comp_background_primary"))
    .alignItems(HorizontalAlign.Center)
    .justifyContent(FlexAlign.SpaceBetween)
    .clip(true)
  }
}