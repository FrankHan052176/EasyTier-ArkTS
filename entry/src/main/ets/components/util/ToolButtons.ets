import { BusinessError, pasteboard } from "@kit.BasicServicesKit"
import { Svp2fp } from "../../AppManager"
import { Logger } from "../../util/Logger"

@ComponentV2
export struct ToolButton {
  @Param @Require symbol: Resource
  @Param buttonSize: number = 40
  @Param symbolScale: number = 0.6
  @Param bgColor: ResourceColor = $r("sys.color.comp_background_tertiary")
  @Param symbolColor: Array<ResourceColor> = [$r("sys.color.font_primary")]
  build() {
    Button({ type: ButtonType.Circle }) {
      SymbolGlyph(this.symbol)
        .fontColor(this.symbolColor)
        .fontSize(Svp2fp(this.buttonSize*this.symbolScale))
        .animation({
          curve: Curve.Ease,
          duration: 300
        })
    }
    .width(this.buttonSize).height(this.buttonSize)
    .buttonStyle(ButtonStyleMode.NORMAL)
    .backgroundColor(this.bgColor)
    .animation({
      curve: Curve.Ease,
      duration: 300
    })
  }
}

@ComponentV2
export struct ToolButtonWithText {
  @Param @Require symbol: Resource
  @Param @Require text: string
  @Param bgColor: ResourceColor = $r("sys.color.comp_background_tertiary")
  @Param textColor: ResourceColor = $r("sys.color.font_primary")
  @Param symbolColor: Array<ResourceColor> = [$r("sys.color.font_primary")]
  @Param symbolSize: number = 24
  @Param textSize: number = 18

  build() {
    Button({ type: ButtonType.Capsule }) {
      Row() {
        SymbolGlyph(this.symbol)
          .fontColor(this.symbolColor)
          .fontSize(this.symbolSize)
        Text(this.text)
          .fontColor(this.textColor)
          .fontSize(this.textSize)
      }
      .justifyContent(FlexAlign.SpaceAround)
    }
    .padding({left: 10, right: 10})
    .height(this.symbolSize/6*10)
    .buttonStyle(ButtonStyleMode.NORMAL)
    .backgroundColor(this.bgColor)
  }
}

@ComponentV2
export struct ToolButtonWithPaste {
  @Param pasteCallback: (value: string) => void = () => {}
  build() {
    PasteButton({
      buttonType: ButtonType.Circle,
      text: undefined
    })
      .padding({left: 10, right: 10})
      .height(40)
      .onClick((_event, result) => {
        if (PasteButtonOnClickResult.SUCCESS === result) {
          pasteboard.getSystemPasteboard().getData((err: BusinessError, pasteData: pasteboard.PasteData) => {
            if (err) {
              console.error(`Failed to get paste data. Code is ${err.code}, message is ${err.message}`);
              return;
            }
            this.pasteCallback(pasteData.getPrimaryText())
          });
        }else {
          Logger.debug("failed get perm")
        }
      })
  }
}