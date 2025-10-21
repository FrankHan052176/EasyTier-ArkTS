import { Config, network_whitelist } from "../../util/config/ETConfig"
import { LengthUnit } from "@kit.ArkUI"
import { safeFieldName } from "../../util/Conversion"
import { ItemBuilder } from "../../util/ItemBuilders"
import Logger from "../../util/Logger"

type element_flags = network_whitelist | boolean
function fixFieldName(name: string): string {
  switch (name) {
    case "accept_dns": return "enable_magic_dns"
    case "private_mode": return "enable_private_mode"
    case "enable_ipv6": return "disable_ipv6"
    case "enable_encryption": return "disable_encryption"
    default: return name
  }
}
function fixFieldValue(name: string, value: boolean): boolean {
  switch (name) {
    case "enable_ipv6": return !value
    case "enable_encryption": return !value
    default: return value
  }
}
@ComponentV2
export struct Flags {
  @Param @Require config: Config
  @Local isBig: boolean = false
  @Param @Require comp_width: number

  build() {
    Column() {
      Row() {
        Text("功能开关")
          .fontSize(17)
          .fontColor($r("sys.color.font_primary"))
        Row() {

        }
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
        ForEach(Object.entries(this.config.flags), (entry:[string, element_flags]) => {
          if (!(entry[1] instanceof network_whitelist) && !(safeFieldName(entry[0]).startsWith("_"))) {
            ItemBuilder({
              item: $r("app.string."+ fixFieldName(safeFieldName(entry[0]))),
              isSelected: fixFieldValue(safeFieldName(entry[0]), (this.config.flags as ESObject)[safeFieldName(entry[0])] as boolean),
              itemWidth: (this.comp_width-40)/3,
              itemHeight: 40
            })
              .onAppear(() => {
                Logger.debug(safeFieldName(entry[0]))
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
      }
      .width('100%')
    }
    .width(this.comp_width)
    .alignItems(HorizontalAlign.Center)
    .borderRadius(18)
    .backgroundColor($r("sys.color.comp_background_primary"))
    .padding({top: 15, left: 10, right: 10, bottom: 10})
  }
}