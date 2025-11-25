import Manager from "../../Manager"
import { Config } from "../../util/ETConfig"
import { PermissionUtil } from "../../PermissionUtil"

@ComponentV2
export struct Hostname {
  @Param @Require config:Config
  @Param @Require comp_width: number

  build() {
    Column() {
      Row(){
        Text($r("app.string.hostname"))
          .fontSize(18)
          .fontColor($r("sys.color.font_primary"))
        Row() {
          Text("使用设备名")
            .fontSize(16)
            .fontColor($r("sys.color.font_primary"))
          SymbolGlyph($r("sys.symbol.square_and_arrow_down"))
            .fontSize(18)
            .fontColor([$r("sys.color.font_primary")])
            .effectStrategy(SymbolEffectStrategy.HIERARCHICAL)
        }
        .onClick(() => {
          PermissionUtil.requestDistributePerm(this.getUIContext().getHostContext()!).then((value) => {
            this.config.hostname = value?Manager.deviceManager.getLocalDeviceName():"HarmonyOS"
          })
        })
        .clickEffect({
          level: ClickEffectLevel.LIGHT
        })
      }
      .padding({left: 5, bottom: 5})
      .width('100%')
      .justifyContent(FlexAlign.SpaceBetween)
      .alignItems(VerticalAlign.Center)
      TextInput({text: this.config.hostname, placeholder: $r("app.string.hostname_placeholder")})
        .contentType(ContentType.NICKNAME)
        .fontSize(16)
        .padding(8)
        .borderRadius(10)
        .onChange((newText: string) => {
          this.config.hostname = newText
        })
    }
    .width(this.comp_width)
    .alignItems(HorizontalAlign.Start)
    .borderRadius(18)
    .backgroundColor($r("sys.color.comp_background_primary"))
    .padding({top: 15, left: 10, bottom: 10, right: 10})
  }
}