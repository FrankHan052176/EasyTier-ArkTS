import { Config, network_whitelist } from "../../util/config/ETConfig"
import { LengthUnit } from "@kit.ArkUI"
import Logger from "../../util/Logger"
import { safeFieldName } from "../../util/Conversion"
import Manager from "../../Manager"

type element_flags = network_whitelist | boolean
const minWidth = 350
@ComponentV2
export struct Flags {
  @Param @Require config: Config
  @Local isBig: boolean = false
  @Computed
  get comp_width() {
    return Manager.width>=Manager.height*0.625?minWidth:Manager.width-20
  }

  build() {
    Column() {
      Row() {
        Text("功能开关")
          .fontSize(17)
          .fontColor($r("sys.color.font_primary"))
        Row() {
          Text(this.isBig?"折叠":"展开")
            .fontSize(16)
            .fontColor($r("sys.color.font_primary"))
          SymbolGlyph(this.isBig?$r("sys.symbol.arrow_down_right_and_arrow_up_left"):$r("sys.symbol.arrow_up_left_and_arrow_down_right"))
            .fontColor([$r("sys.color.font_primary")])
            .width(18)
            .height(18)
            .effectStrategy(SymbolEffectStrategy.SCALE)
        }
        .onClick(() => {
          animateToImmediately({
            curve: Curve.LinearOutSlowIn,
            duration: 300
          }, () => {
            this.isBig = !this.isBig
          })
        })
        .clickEffect({
          level: ClickEffectLevel.LIGHT
        })
      }
      .justifyContent(FlexAlign.SpaceBetween)
      .width('100%')
      .padding({left: 5, bottom: 5})
      Flex({
        wrap: FlexWrap.Wrap,
        space: {
          main: {
            value: 10,
            unit: LengthUnit.VP
          },
          cross: {
            value: 10,
            unit: LengthUnit.VP
          }
        }
      }) {
        if (this.isBig) {
          ForEach(Object.entries(this.config.flags), (entry:[string, element_flags]) => {
            if (!(entry[1] instanceof network_whitelist) && !(safeFieldName(entry[0]).startsWith("_"))) {
              Button($r("app.string."+ safeFieldName(entry[0])), {
                type: ButtonType.Normal,
                buttonStyle: (this.config.flags as ESObject)[entry[0].substring(5)]?ButtonStyleMode.EMPHASIZED:ButtonStyleMode.NORMAL,
                role: ButtonRole.NORMAL
              })
                .fontSize(12)
                .padding(8)
                .borderRadius(13)
                .clickEffect({
                  level: ClickEffectLevel.LIGHT,
                  scale: 0.9
                })
                .onClick(() => {
                  animateToImmediately({
                    curve: Curve.Friction,
                    duration: 200,
                    expectedFrameRateRange: {
                      min: 30,
                      max: 120,
                      expected: 120
                    }
                  }, () => {
                    (this.config.flags as ESObject)[entry[0].substring(5)] = !(this.config.flags as ESObject)[entry[0].substring(5)]
                  })
                })
                .geometryTransition(this.config.instance_id+entry[0])
            }
          }, (value: [string, element_flags], index) => {return "flags_element_"+index})
        }else {
          ForEach(Object.entries(this.config.flags), (entry:[string, element_flags]) => {
            if (!(entry[1] instanceof network_whitelist) && !(safeFieldName(entry[0]).startsWith("_")) && entry[1] == true) {
              ListItem() {
                Button($r("app.string."+ safeFieldName(entry[0])), {
                  type: ButtonType.Normal,
                  buttonStyle: ButtonStyleMode.EMPHASIZED,
                  role: ButtonRole.NORMAL
                })
                  .fontSize(12)
                  .padding(8)
                  .borderRadius(13)
              }
              .geometryTransition(this.config.instance_id+entry[0])
            }
          }, (value: [string, element_flags], index) => {return "flags_element_"+index})
        }
      }
      .width('100%')
    }
    .width(this.comp_width)
    .alignItems(HorizontalAlign.Center)
    .borderRadius(18)
    .backgroundColor($r("sys.color.comp_background_primary"))
    .padding(10)
  }
}