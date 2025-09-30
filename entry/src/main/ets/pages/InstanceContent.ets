import { Config } from "../util/config/ETConfig"
import { Hostname } from "./content/Hostname"
import { IPv4 } from "./content/IPv4"
import { LengthUnit } from "@kit.ArkUI"
import { Profiles } from "./content/Profiles"
import Manager from "../Manager"
import { Peers } from "./content/Peers"
import { Flags } from "./content/Flags"
import { ProxyCIDRs } from "./content/ProxyCIDRs"
import { Listeners } from "./content/Listeners"
import { Whitelist } from "./content/Whitelist"
import { Routes } from "./content/Routes"
import { ExitNodes } from "./content/ExitNodes"
import { WGPortal } from "./content/WGPortal"
import { Socks5 } from "./content/Socks5"

@ComponentV2
export struct InstanceContent {
  @Param @Require config:Config

  build() {
    Scroll() {
      Column() {
        Text("基础设置")
          .fontSize(12)
          .fontColor($r("sys.color.font_secondary"))
          .margin({left: 10, bottom: 5, top: 66})
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
          IPv4({config: this.config})
          Hostname({config: this.config})
          Profiles({config: this.config})
          Peers({config: this.config})
        }
        .width('100%')
        .margin({bottom: 10})
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.START, SafeAreaEdge.BOTTOM])
        Text("高级设置")
          .fontSize(12)
          .fontColor($r("sys.color.font_secondary"))
          .margin({left: 10, bottom: 5})
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
          Flags({config: this.config})
          ProxyCIDRs({config: this.config})
          Listeners({config: this.config})
          Whitelist({config: this.config})
          Routes({config: this.config})
          ExitNodes({config: this.config})
          WGPortal({config: this.config})
          Socks5({config: this.config})
          // TODO 监听映射
          // TODO 端口映射
        }
        .width('100%')
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.START, SafeAreaEdge.BOTTOM])
        Blank()
          .height(Manager.height*0.1)
          .width('100%')
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.START, SafeAreaEdge.BOTTOM])
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.START, SafeAreaEdge.BOTTOM])
    }
    .scrollBar(BarState.Off)
    .width('100%')
    .height(Manager.height-95)
    .align(Alignment.Top)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.START, SafeAreaEdge.BOTTOM])
    .edgeEffect(EdgeEffect.Spring)
  }
}