import Manager from "../../Manager"
import { Config, vpn_portal_config } from "../../util/ETConfig"
@Extend(TextInput) function fancyTextInput(enable: boolean, weight: number = 30, length: number = 3) {
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
// @Extend(TextInput) function fancyTextInput(width: number = 30, length: number = 3) {
//   .padding(0)
//   .fontSize(16)
//   .width(width)
//   .maxLength(length)
//   .borderRadius(0)
//   .type(InputType.Number)
//   .backgroundColor(Color.Transparent)
//   .selectedBackgroundColor(Color.Transparent)
//   .textAlign(TextAlign.Center)
// }
@Extend(Text) function fancyText() {
  .padding(0)
  .fontSize(16)
  .borderRadius(0)
  .backgroundColor(Color.Transparent)
}

@ComponentV2
export struct WGPortal {
  @Param @Require config:Config
  @Local ip1: string = "10"
  @Local ip2: string = "0"
  @Local ip3: string = "1"
  @Local ip4: string = "0"
  @Local port: string = "22020"
  @Param @Require comp_width: number

  updateCIDR() {
    if (this.config.vpn_portal_config !== null) {
      this.config.vpn_portal_config!.client_cidr = this.ip1+"."+this.ip2+"."+this.ip3+"."+this.ip4+"/24"
    }
  }

  updateListener() {
    if (this.config.vpn_portal_config !== null) {
      this.config.vpn_portal_config!.wireguard_listen = "0.0.0.0:"+this.port
    }
  }

  readCIDR() {
    if (this.config.vpn_portal_config !== null) {
      let split = this.config.vpn_portal_config.client_cidr.substring(0, this.config.vpn_portal_config.client_cidr.length-3).split(".")
      this.ip1 = split[0]
      this.ip2 = split[1]
      this.ip3 = split[2]
      this.ip4 = split[3]
      this.port = this.config.vpn_portal_config.wireguard_listen.substring(8)
    }else {
      this.ip1 = "10"
      this.ip2 = "0"
      this.ip3 = "1"
      this.ip4 = "0"
      this.port = "22020"
    }
  }

  aboutToAppear(): void {
    this.readCIDR()
  }

  @Builder
  WrappedInput() {
    Row() {
      Row() {
        TextInput({text: $$this.ip1})
          .fancyTextInput(this.config.vpn_portal_config===null)
          .onChange((value) => {
            this.ip1 = value
            this.updateCIDR()
          })
        Text(".")
          .fontColor(this.config.vpn_portal_config===null?$r("sys.color.font_secondary"):$r("sys.color.font_primary"))
          .fancyText()
        TextInput({text: $$this.ip2})
          .fancyTextInput(this.config.vpn_portal_config===null)
          .onChange((value) => {
            this.ip2 = value
            this.updateCIDR()
          })
        Text(".")
          .fontColor(this.config.vpn_portal_config===null?$r("sys.color.font_secondary"):$r("sys.color.font_primary"))
          .fancyText()
        TextInput({text: $$this.ip3})
          .fancyTextInput(this.config.vpn_portal_config===null)
          .onChange((value) => {
            this.ip3 = value
            this.updateCIDR()
          })
        Text(".")
          .fontColor(this.config.vpn_portal_config===null?$r("sys.color.font_secondary"):$r("sys.color.font_primary"))
          .fancyText()
        TextInput({text: $$this.ip4})
          .fancyTextInput(this.config.vpn_portal_config===null)
          .onChange((value) => {
            this.ip4 = value
            this.updateCIDR()
          })
      }
      .layoutWeight(60)
      .borderRadius(10)
      .padding({top: 5, bottom: 5, right: 5})
      .backgroundColor($r("sys.color.interactive_hover"))
      Row() {
        TextInput({text: $$this.port})
          .fancyTextInput(this.config.vpn_portal_config===null, 60, 5)
          .onChange((value) => {
            this.port = value
            this.updateListener()
          })
      }
      .width(60)
      .borderRadius(10)
      .padding({top: 5, bottom: 5})
      .backgroundColor($r("sys.color.interactive_hover"))
      .margin({left: 10})
    }
    .enabled(this.config.vpn_portal_config !== null)
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .justifyContent(FlexAlign.Start)
    .animation({
      curve: Curve.LinearOutSlowIn,
      duration: 300,
      expectedFrameRateRange: {
        min: 30,
        max: 120,
        expected: 120
      }
    })
  }

  build() {
    Column() {
      Row() {
        Text("VPN Portal")
          .fontSize(17)
          .fontColor($r("sys.color.font_primary"))
        Button('启用', {
          type: ButtonType.Normal,
          buttonStyle: this.config.vpn_portal_config!==null?ButtonStyleMode.EMPHASIZED:ButtonStyleMode.NORMAL,
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
              curve: Curve.EaseIn,
              duration: 300,
              expectedFrameRateRange: {
                min: 30,
                max: 120,
                expected: 120
              }
            }, () => {
              if (this.config.vpn_portal_config === null) {
                this.config.initPortal()
                this.readCIDR()
              }else {
                this.config.vpn_portal_config = null
              }
            })
          })
      }
      .padding({left: 5})
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .justifyContent(FlexAlign.SpaceBetween)
      Column() {
        this.WrappedInput()
      }
      .clip(true)
      .width('100%')
      .padding({top: 5})
      .alignItems(HorizontalAlign.Center)
    }
    .width(this.comp_width)
    .padding({left: 10, right: 10, top: 10, bottom: 10})
    .borderRadius(18)
    .backgroundColor($r("sys.color.comp_background_primary"))
    .alignItems(HorizontalAlign.Center)
  }
}