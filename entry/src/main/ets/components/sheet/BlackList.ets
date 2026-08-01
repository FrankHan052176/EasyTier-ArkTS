import { AppManager } from "../../AppManager"
import { Logger } from "../../shared/logging/Logger"
import { sendToast } from "../../ToastUtil"
import { ToolButton } from "../util/ToolButtons"

export class AppInfo {
  pkgName: string
  name: string
  icon: string
  enable: boolean = true

  constructor(pkgName: string, name: string, icon: string) {
    this.pkgName = pkgName
    this.name = name
    this.icon = icon
  }
}

@ComponentV2
export struct BlackList_Content {
  @Local text: string = ""

  private isRuntimeLocked(): boolean {
    return AppManager.easytier.hasActiveOrStartingRuntime()
  }

  private addApp(): void {
    if (this.isRuntimeLocked()) {
      sendToast('实例运行中，请停止后再修改 App 过滤列表', $r('sys.symbol.exclamationmark_circle'), 1)
      return
    }
    const pkgName = this.text.trim()
    if (pkgName.length <= 0) {
      this.text = ""
      return
    }
    Logger.debug("text: " + pkgName)
    AppManager.web.getAppInfo(pkgName, (name, icon) => {
      AppManager.preference.setAppInfo(pkgName, name, icon)
      this.text = ""
    })
  }

  @Builder
  addRow() {
    ListItem() {
      Row({ space: 8 }) {
        TextInput({ text: this.text, placeholder: "输入 App 包名" })
          .id("pkgName_input")
          .layoutWeight(1)
          .height(38)
          .padding({ left: 10, right: 10 })
          .backgroundColor($r("sys.color.comp_background_tertiary"))
          .borderRadius(12)
          .enabled(!this.isRuntimeLocked())
          .onChange((value) => {
            this.text = value
          })
        Button("添加", { type: ButtonType.Normal, buttonStyle: ButtonStyleMode.EMPHASIZED, role: ButtonRole.NORMAL })
          .borderRadius(13)
          .enabled(!this.isRuntimeLocked())
          .onClick(() => {
            this.addApp()
          })
      }
      .width('100%')
      .height(54)
      .padding({ left: 10, right: 10, top: 7, bottom: 7 })
      .borderRadius(18)
      .backgroundColor($r("sys.color.comp_background_primary"))
      .shadow({
        radius: 7,
        color: '#1F000000'
      })
    }
  }

  @Builder
  rightButton(pkgName: string) {
    Row() {
      ToolButton({
        symbol: $r("sys.symbol.trash"),
        buttonSize: 40,
        bgColor: $r("sys.color.background_secondary"),
        symbolColor: [$r("sys.color.warning")]
      })
        .enabled(!AppManager.easytier.hasActiveOrStartingRuntime())
        .margin({
          left: 10,
          right: 10
        })
        .onClick(() => {
          AppManager.preference.delAppInfo(pkgName)
        })
    }
  }
  build() {
    List({space: 8}) {
      ListItem()
        .height(64)

      if (this.isRuntimeLocked()) {
        ListItem() {
          Text('实例运行中，停止后可修改过滤模式与 App 列表')
            .width('100%')
            .fontSize(13)
            .fontColor($r('sys.color.font_secondary'))
            .padding({ left: 12, right: 12, top: 8, bottom: 8 })
        }
      }

      this.addRow()

      ForEach(Array.from(AppManager.preference.black_list_apps.keys()), (app: string) => {
        ListItem() {
          BlackListItem({ app: app })
        }
        .swipeAction({
          end: this.rightButton(app)
        })
      }, (item: string) => item)
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Off)
    .padding({
      left: 16,
      right: 16,
      top: 12,
      bottom: 12
    })
  }
}

@ComponentV2
struct BlackListItem {
  @Param @Require app: string
  @Local info: AppInfo | undefined = AppManager.preference.getAppInfo(this.app)

  build() {
    Row({space: 8}) {
      Row({space: 4}) {
        Image(this.info?.icon)
          .width(48)
          .height(48)
          .autoResize(true)
        Column({space: 4}) {
          Text(this.info?.name ?? "N/A")
            .fontColor($r("sys.color.font_primary"))
            .minFontSize(0)
            .maxFontSize(24)
            .maxLines(1)
            .constraintSize({
              minHeight: 20,
              maxHeight: '100%'
            })
          Text(this.app)
            .fontColor($r("sys.color.font_secondary"))
            .fontSize(12)
            .maxLines(1)
        }
        .alignItems(HorizontalAlign.Start)
        .justifyContent(FlexAlign.SpaceBetween)
        .height(48)
        .padding({top: 4, bottom: 4})
      }
      Toggle({ type: ToggleType.Switch, isOn: this.info?.enable ?? false })
        .selectedColor($r("sys.color.brand"))
        .switchPointColor(Color.White)
        .enabled(!AppManager.easytier.hasActiveOrStartingRuntime())
        .onChange((isOn: boolean) => {
          if (this.info) {
            this.info.enable = isOn
            AppManager.preference.updateAppInfo(this.info)
          }
        })
    }
    .width('100%')
    .padding({
      left: 16,
      right: 16,
      top: 16,
      bottom: 16
    })
    .borderRadius(14)
    .backgroundColor($r("sys.color.background_secondary"))
    .alignItems(VerticalAlign.Center)
    .justifyContent(FlexAlign.SpaceBetween)
  }
}
