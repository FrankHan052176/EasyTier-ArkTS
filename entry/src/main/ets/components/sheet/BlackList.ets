import { EditableLeftIconType, EditableTitleBar, LengthMetrics } from "@kit.ArkUI"
import { EventHelper } from "../../util/EventHelper"
import { AppManager } from "../../AppManager"
import { Logger } from "../../util/Logger"
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
export struct BlackList_Title {
  @Local menu: boolean = false
  @Local text: string = ""

  @Monitor("menu")
  addApp() {
    if (!this.menu) {
      if (this.text.length > 0) {
        Logger.debug("text: "+this.text)
        AppManager.web.getAppInfo(this.text, (name, icon) => {
          AppManager.preference.setAppInfo(this.text, name, icon)
          this.text = ""
        })
      }else {
        this.text = ""
      }
    }
  }

  @Builder
  pkgInput() {
    TextInput({text: this.text})
      .id("pkgName_input")
      .backgroundColor($r("sys.color.background_primary"))
      .borderRadius(0)
      .onEditChange((isEdit) => {
        if (!isEdit) {
          this.menu = false
        }
      })
      .onChange((value) => {
        this.text = value
      })
  }

  build() {
    Stack({alignContent: Alignment.End}) {
      EditableTitleBar({
        leftIconStyle: EditableLeftIconType.Back,
        title: 'App 黑名单',
        contentMargin: {
          start: LengthMetrics.vp(0), end: LengthMetrics.vp(0),
        },
        isSaveIconRequired: false,
        onCancel: () => {
          EventHelper.emitterPublish("home_close_sheet")
        }
      })
      ToolButton({
        symbol: $r("sys.symbol.plus"),
        buttonSize: 40,
        bgColor: $r("sys.color.background_secondary"),
        symbolColor: [$r("sys.color.font_primary")]
      })
        .rotate({
          angle: this.menu?45:0
        })
        .animation({
          duration: 300,
          curve: Curve.Friction
        })
        .onClick(() => {
          this.menu = !this.menu
          if (this.menu) {
            setTimeout(() => {
              try {
                this.getUIContext().getFocusController().requestFocus("pkgName_input");
              } catch (e) {
                Logger.error("requestFocus error: " + JSON.stringify(e), "BlackList_Title")
              }
            }, 50)
          }
        })
        .bindContextMenu(this.menu!!, this.pkgInput(), {
          placement: Placement.BottomRight,
          backgroundColor: $r("sys.color.background_primary")
        })
    }
  }
}

@ComponentV2
export struct BlackList_Content {
  @Builder
  rightButton(pkgName: string) {
    Row() {
      ToolButton({
        symbol: $r("sys.symbol.trash"),
        buttonSize: 40,
        bgColor: $r("sys.color.background_secondary"),
        symbolColor: [$r("sys.color.warning")]
      })
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