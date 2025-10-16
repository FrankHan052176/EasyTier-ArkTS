import Manager from "../Manager"
import { Config } from "../util/config/ETConfig"
import Logger from "../util/Logger"
import { ToolButton } from "./Components"
import { requestLocPerm } from "../util/Permission"

@ComponentV2
export struct InstanceCard {
  @Param @Require config:Config
  @Param bgColor: ResourceColor = $r("sys.color.comp_background_primary")
  @Param fontColor: ResourceColor = $r("sys.color.font_primary")
  @Param secondaryColor: ResourceColor = $r("sys.color.font_secondary")
  @Param itemHeight: number = 80
  @Param switchHighlight: boolean = true
  @Local isHighlight: boolean = false
  @Local highlightPos: [number, number] = [-999, -999]
  build() {
    Row() {
      Column() {
        Text(this.config.instance_name)
          .fontSize(18)
          .fontColor(this.fontColor)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .height(18)
        Text(this.config.instance_id)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('30%')
          .fontSize(10)
          .fontColor(this.secondaryColor)
          .height(14)
          .align(Alignment.Bottom)
      }
      .alignItems(HorizontalAlign.Start)
      .justifyContent(FlexAlign.Center)
      ToolButton({
        symbol: Manager.infos.has(this.config.instance_id)?$r("sys.symbol.pause"):$r("sys.symbol.play_fill"),
        symbolColor: [this.fontColor]
      })
        .onClick(() => {
          if (Manager.infos.has(this.config.instance_id)) {
            if (!Manager.stopInstance(this.config)) {
              Logger.error("关闭网络失败")
            }
          }else {
            if (Manager.infos.size > 0) {
              this.getUIContext().getPromptAction().showToast({
                message: "请先关闭正在运行的网络"
              })
            }else {
              requestLocPerm(this.getUIContext().getHostContext()!).then((value) => {
                if (!value) {
                  this.getUIContext().getPromptAction().showToast({
                    message: "拒绝授权定位权限将无法进行后台保活"
                  })
                }
                Manager.startInstance(this.config)
              })
            }
          }
        })
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .justifyContent(FlexAlign.SpaceBetween)
    .backgroundColor(this.bgColor)
    .padding({top: 8, bottom: 8, left: 12, right: 12})
    .borderRadius(18)
    .clickEffect({
      level: ClickEffectLevel.LIGHT
    })
  }
}