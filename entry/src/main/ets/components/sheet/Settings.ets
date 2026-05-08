import { AppManager } from '../../AppManager'
import { HMRouterMgr } from '@hadss/hmrouter'
import { APP_VERSION, APP_VERSION_CODE, BUILD_TIME, CORE_VERSION } from '../../util/info/BuildTime'
import { EditableLeftIconType, EditableTitleBar, LengthMetrics } from '@kit.ArkUI'
import { EventHelper } from '../../util/EventHelper'
import { deviceInfo } from '@kit.BasicServicesKit'

@ComponentV2
export struct Setting_Title {
  build() {
    EditableTitleBar({
      leftIconStyle: EditableLeftIconType.Back,
      title: '设置',
      contentMargin: {
        start: LengthMetrics.vp(0),
        end: LengthMetrics.vp(0),
      },
      isSaveIconRequired: false,
      onCancel: () => {
        EventHelper.emitterPublish("home_close_sheet")
      }
    })
  }
}

@Builder
function settingGroupHeader(title: string) {
  Text(title)
    .width('100%')
    .fontSize(14)
    .fontColor($r("sys.color.font_secondary"))
    .padding({ top: 10, left: 5, bottom: 3 })
}

@Builder
export function Setting_Sheet() {
  List() {
    ListItem() {
      Row() {
        Row() {
          SymbolGlyph($r("sys.symbol.house"))
            .fontColor([$r("sys.color.font_primary")])
            .fontSize(16)
            .margin({ right: 5 })
          Text("内核版本")
            .fontColor($r("sys.color.font_primary"))
            .fontSize(16)
        }

        Text(CORE_VERSION)
          .fontColor($r("sys.color.font_primary"))
          .fontSize(16)
          .margin({ right: 5 })
      }
      .height(49)
      .borderRadius(18)
      .alignItems(VerticalAlign.Center)
      .justifyContent(FlexAlign.SpaceBetween)
      .width('100%')
      .backgroundColor($r("sys.color.background_secondary"))
      .padding({
        left: 10,
        right: 5,
        top: 5,
        bottom: 5
      })
      .gesture(TapGesture({ count: 10 })
        .onAction(() => {
          AppManager.uiState.dev = !AppManager.uiState.dev
        })
      )
    }
    .margin({ bottom: 10 })

    ListItem() {
      Row() {
        Row() {
          SymbolGlyph($r("sys.symbol.house_fill"))
            .fontColor([$r("sys.color.font_primary")])
            .fontSize(16)
            .margin({ right: 5 })
          Text("子进程模式")
            .fontColor($r("sys.color.font_primary"))
            .fontSize(16)
            .margin({ right: 5 })
        }

        Toggle({ type: ToggleType.Switch, isOn: AppManager.uiState.ext_mode })
          .selectedColor($r('sys.color.brand'))
          .switchPointColor($r('sys.color.comp_background_list_card'))
          .onChange((isOn: boolean) => {
            AppManager.uiState.ext_mode = isOn
          })
          .height(29)
          .width(52)
      }
      .height(49)
      .borderRadius(18)
      .alignItems(VerticalAlign.Center)
      .justifyContent(FlexAlign.SpaceBetween)
      .width('100%')
      .backgroundColor($r("sys.color.background_secondary"))
      .padding(10)
    }
    .margin({ bottom: 10 })

    ListItem() {
      Row() {
        Row() {
          SymbolGlyph($r("sys.symbol.square_fill_grid_2x2"))
            .fontColor([$r("sys.color.font_primary")])
            .fontSize(16)
            .margin({ right: 5 })
          Text("APP版本")
            .fontColor($r("sys.color.font_primary"))
            .fontSize(16)
        }

        Text(APP_VERSION + "(" + APP_VERSION_CODE + ")")
          .fontColor($r("sys.color.font_primary"))
          .fontSize(16)
          .margin({ right: 5 })
      }
      .height(49)
      .borderRadius(18)
      .alignItems(VerticalAlign.Center)
      .justifyContent(FlexAlign.SpaceBetween)
      .width('100%')
      .backgroundColor($r("sys.color.background_secondary"))
      .padding({
        left: 10,
        right: 5,
        top: 5,
        bottom: 5
      })
    }
    .margin({ bottom: 10 })

    ListItem() {
      Row() {
        Row() {
          SymbolGlyph($r("sys.symbol.square_fill_grid_2x2"))
            .fontColor([$r("sys.color.font_primary")])
            .fontSize(16)
            .margin({ right: 5 })
          Text("编译时间")
            .fontColor($r("sys.color.font_primary"))
            .fontSize(16)
        }

        Text(BUILD_TIME)
          .fontColor($r("sys.color.font_primary"))
          .fontSize(16)
          .margin({ right: 5 })
      }
      .height(49)
      .borderRadius(18)
      .alignItems(VerticalAlign.Center)
      .justifyContent(FlexAlign.SpaceBetween)
      .width('100%')
      .backgroundColor($r("sys.color.background_secondary"))
      .padding({
        left: 10,
        right: 5,
        top: 5,
        bottom: 5
      })
    }
    .margin({ bottom: 10 })

    ListItem() {
      Row() {
        Row() {
          SymbolGlyph($r("sys.symbol.disconnect"))
            .fontColor([$r("sys.color.font_primary")])
            .fontSize(16)
            .margin({ right: 5 })
          Text("UI 设置")
            .fontColor($r("sys.color.font_primary"))
            .fontSize(16)
        }

        SymbolGlyph($r("sys.symbol.arrow_right"))
          .fontColor([$r("sys.color.font_primary")])
          .fontSize(16)
          .margin({ right: 5 })
      }
      .height(49)
      .borderRadius(18)
      .alignItems(VerticalAlign.Center)
      .justifyContent(FlexAlign.SpaceBetween)
      .width('100%')
      .backgroundColor($r("sys.color.background_secondary"))
      .padding({
        left: 10,
        right: 5,
        top: 5,
        bottom: 5
      })
      .clickEffect({
        level: ClickEffectLevel.LIGHT
      })
      .onClick(() => {
        EventHelper.emitterPublish("home_close_sheet")
        setTimeout(() => {
          EventHelper.emitterPublish("home_open_sheet", {
            data: {
              type: "ui"
            }
          })
        }, 10)
      })
    }
    .margin({ bottom: 10 })

    ListItem() {
      Row() {
        Row() {
          SymbolGlyph($r("sys.symbol.list_xmark"))
            .fontColor([$r("sys.color.font_primary")])
            .fontSize(16)
            .margin({ right: 5 })
          Text(AppManager.uiState.white_list?"App 白名单":"App 黑名单")
            .fontColor($r("sys.color.font_primary"))
            .fontSize(16)
        }

        SymbolGlyph($r("sys.symbol.arrow_right"))
          .fontColor([$r("sys.color.font_primary")])
          .fontSize(16)
          .margin({ right: 5 })
      }
      .height(49)
      .borderRadius(18)
      .alignItems(VerticalAlign.Center)
      .justifyContent(FlexAlign.SpaceBetween)
      .width('100%')
      .backgroundColor($r("sys.color.background_secondary"))
      .padding({
        left: 10,
        right: 5,
        top: 5,
        bottom: 5
      })
      .clickEffect({
        level: ClickEffectLevel.LIGHT
      })
      .onClick(() => {
        EventHelper.emitterPublish("home_close_sheet")
        setTimeout(() => {
          EventHelper.emitterPublish("home_open_sheet", {
            data: {
              type: "black_list"
            }
          })
        }, 10)
      })
    }
    .margin({ bottom: 10 })

    ListItemGroup({ header: settingGroupHeader("高级") }) {
      ListItem() {
        Row() {
          Row() {
            SymbolGlyph($r("sys.symbol.exclamationmark_message_middle_bottom"))
              .fontColor([$r("sys.color.font_primary")])
              .fontSize(16)
              .margin({ right: 5 })
            Text("收集EasyTier日志")
              .fontColor($r("sys.color.font_primary"))
              .fontSize(16)
              .margin({ right: 5 })
            if (AppManager.uiState.inittedLog != AppManager.uiState.show_log) {
              Text("重启后生效")
                .fontColor($r("sys.color.font_secondary"))
                .fontSize(14)
            }
          }

          Toggle({ type: ToggleType.Switch, isOn: AppManager.uiState.show_log })
            .selectedColor($r('sys.color.brand'))
            .switchPointColor($r('sys.color.comp_background_list_card'))
            .onChange((isOn: boolean) => {
              AppManager.uiState.show_log = isOn
            })
            .height(29)
            .width(52)
        }
        .height(49)
        .borderRadius(18)
        .alignItems(VerticalAlign.Center)
        .justifyContent(FlexAlign.SpaceBetween)
        .width('100%')
        .backgroundColor($r("sys.color.background_secondary"))
        .padding(10)
      }
      .margin({ bottom: 10 })

      ListItem() {
        Row() {
          Row() {
            SymbolGlyph($r("sys.symbol.doc"))
              .fontColor([$r("sys.color.font_primary")])
              .fontSize(16)
              .margin({ right: 5 })
            Text("分享日志")
              .fontColor($r("sys.color.font_primary"))
              .fontSize(16)
          }
          Button('分享', { type: ButtonType.Normal, buttonStyle: ButtonStyleMode.EMPHASIZED, role: ButtonRole.NORMAL })
            .borderRadius(13)
            .onClick(() => {
              AppManager.easytier.writeAndShareLogs()
            })
        }
        .height(49)
        .borderRadius(18)
        .alignItems(VerticalAlign.Center)
        .justifyContent(FlexAlign.SpaceBetween)
        .width('100%')
        .backgroundColor($r("sys.color.background_secondary"))
        .padding({
          left: 10,
          right: 5,
          top: 5,
          bottom: 5
        })
      }
      .margin({ bottom: 10 })

      if (deviceInfo.sdkApiVersion < 20) {
        ListItem() {
          Row() {
            Row() {
              SymbolGlyph($r("sys.symbol.list_square_bill"))
                .fontColor([$r("sys.color.font_primary")])
                .fontSize(16)
                .margin({ right: 5 })
              Text("路由表模式")
                .fontColor($r("sys.color.font_primary"))
                .fontSize(16)
                .margin({ right: 5 })
            }

            Toggle({ type: ToggleType.Switch, isOn: AppManager.uiState.vpn_routes })
              .selectedColor($r('sys.color.brand'))
              .switchPointColor($r('sys.color.comp_background_list_card'))
              .onChange((isOn: boolean) => {
                AppManager.uiState.vpn_routes = isOn
              })
              .height(29)
              .width(52)
          }
          .height(49)
          .borderRadius(18)
          .alignItems(VerticalAlign.Center)
          .justifyContent(FlexAlign.SpaceBetween)
          .width('100%')
          .backgroundColor($r("sys.color.background_secondary"))
          .padding(10)
        }
      }

      ListItem() {
        Row() {
          Row() {
            SymbolGlyph($r("sys.symbol.person"))
              .fontColor([$r("sys.color.font_primary")])
              .fontSize(16)
              .margin({ right: 5 })
            Text("高级模式")
              .fontColor($r("sys.color.font_primary"))
              .fontSize(16)
              .margin({ right: 5 })
          }

          Toggle({ type: ToggleType.Switch, isOn: AppManager.uiState.dev })
            .selectedColor($r('sys.color.brand'))
            .switchPointColor($r('sys.color.comp_background_list_card'))
            .onChange((isOn: boolean) => {
              AppManager.uiState.dev = isOn
            })
            .height(29)
            .width(52)
        }
        .height(49)
        .borderRadius(18)
        .alignItems(VerticalAlign.Center)
        .justifyContent(FlexAlign.SpaceBetween)
        .width('100%')
        .backgroundColor($r("sys.color.background_secondary"))
        .padding(10)
      }
      .margin({ bottom: 10 })

      if (AppManager.uiState.dev) {
        ListItem() {
          Row() {
            Row() {
              SymbolGlyph($r("sys.symbol.unknown_device"))
                .fontColor([$r("sys.color.font_primary")])
                .fontSize(16)
                .margin({ right: 5 })
              Text("自定义DNS")
                .fontColor($r("sys.color.font_primary"))
                .fontSize(16)
                .margin({ right: 5 })
            }

            TextInput({ text: AppManager.uiState.dns, placeholder: "223.5.5.5" })
              .padding(0)
              .textAlign(TextAlign.End)
              .backgroundColor(Color.Transparent)
              .height('100%')
              .layoutWeight(1)
              .onChange((value) => {
                if (value.length > 0) {
                  AppManager.uiState.dns = value
                }else {
                  AppManager.uiState.dns = "223.5.5.5"
                }
              })
          }
          .height(49)
          .borderRadius(18)
          .alignItems(VerticalAlign.Center)
          .justifyContent(FlexAlign.SpaceBetween)
          .width('100%')
          .backgroundColor($r("sys.color.background_secondary"))
          .padding({ left: 10, right: 10 })
        }
        .margin({ bottom: 10 })

        ListItem() {
          Row() {
            Row() {
              SymbolGlyph($r("sys.symbol.person"))
                .fontColor([$r("sys.color.font_primary")])
                .fontSize(16)
                .margin({ right: 5 })
              Text("添加全局路由")
                .fontColor($r("sys.color.font_primary"))
                .fontSize(16)
                .margin({ right: 5 })
            }

            Toggle({ type: ToggleType.Switch, isOn: AppManager.uiState.force_global })
              .selectedColor($r('sys.color.brand'))
              .switchPointColor($r('sys.color.comp_background_list_card'))
              .onChange((isOn: boolean) => {
                AppManager.uiState.force_global = isOn
              })
              .height(29)
              .width(52)
          }
          .height(49)
          .borderRadius(18)
          .alignItems(VerticalAlign.Center)
          .justifyContent(FlexAlign.SpaceBetween)
          .width('100%')
          .backgroundColor($r("sys.color.background_secondary"))
          .padding(10)
        }
        .margin({ bottom: 10 })
      }
    }

    ListItemGroup({ header: settingGroupHeader("权限") }) {
      ListItem() {
        Row() {
          Row() {
            SymbolGlyph($r("sys.symbol.local_and_rectangle"))
              .fontColor([$r("sys.color.font_primary")])
              .fontSize(16)
              .margin({ right: 5 })
            Text("定位权限")
              .fontColor($r("sys.color.font_primary"))
              .fontSize(16)
          }

          if (AppManager.permission.isGetLocPerm()) {
            Text("已授权")
              .fontColor($r("sys.color.font_primary"))
              .fontSize(16)
              .margin({ right: 5 })
          } else {
            Button('授权',
              { type: ButtonType.Normal, buttonStyle: ButtonStyleMode.EMPHASIZED, role: ButtonRole.NORMAL })
              .borderRadius(13)
              .onClick(() => {
                AppManager.permission.requestLocPerm()
              })
          }
        }
        .height(49)
        .borderRadius(18)
        .alignItems(VerticalAlign.Center)
        .justifyContent(FlexAlign.SpaceBetween)
        .width('100%')
        .backgroundColor($r("sys.color.background_secondary"))
        .padding({
          left: 10,
          right: 5,
          top: 5,
          bottom: 5
        })
      }
      .margin({ bottom: 10 })

      ListItem() {
        Row() {
          Row() {
            SymbolGlyph($r("sys.symbol.protein"))
              .fontColor([$r("sys.color.font_primary")])
              .fontSize(16)
              .margin({ right: 5 })
            Text("分布式权限")
              .fontColor($r("sys.color.font_primary"))
              .fontSize(16)
          }

          if (AppManager.permission.isGetDistributePerm()) {
            Text("已授权")
              .fontColor($r("sys.color.font_primary"))
              .fontSize(16)
              .margin({ right: 5 })
          } else {
            Button('授权',
              { type: ButtonType.Normal, buttonStyle: ButtonStyleMode.EMPHASIZED, role: ButtonRole.NORMAL })
              .borderRadius(13)
              .onClick(() => {
                AppManager.permission.requestDistributePerm()
              })
          }
        }
        .height(49)
        .borderRadius(18)
        .alignItems(VerticalAlign.Center)
        .justifyContent(FlexAlign.SpaceBetween)
        .width('100%')
        .backgroundColor($r("sys.color.background_secondary"))
        .padding({
          left: 10,
          right: 5,
          top: 5,
          bottom: 5
        })
      }
      .margin({ bottom: 10 })
    }
    ListItem() {
      Row() {
        Row() {
          SymbolGlyph($r("sys.symbol.local_and_rectangle"))
            .fontColor([$r("sys.color.font_primary")])
            .fontSize(16)
            .margin({ right: 5 })
          Text("通知权限")
            .fontColor($r("sys.color.font_primary"))
            .fontSize(16)
        }

        if (AppManager.permission.isGetNotificationPerm()) {
          Text("已授权")
            .fontColor($r("sys.color.font_primary"))
            .fontSize(16)
            .margin({ right: 5 })
        } else {
          Button('授权',
            { type: ButtonType.Normal, buttonStyle: ButtonStyleMode.EMPHASIZED, role: ButtonRole.NORMAL })
            .borderRadius(13)
            .onClick(() => {
              AppManager.permission.requestNotificationPerm(true)
            })
        }
      }
      .height(49)
      .borderRadius(18)
      .alignItems(VerticalAlign.Center)
      .justifyContent(FlexAlign.SpaceBetween)
      .width('100%')
      .backgroundColor($r("sys.color.background_secondary"))
      .padding({
        left: 10,
        right: 5,
        top: 5,
        bottom: 5
      })
    }
    .margin({ bottom: 10 })

    ListItem() {
      Row() {
        Row() {
          SymbolGlyph($r("sys.symbol.questionmark_circle"))
            .fontColor([$r("sys.color.font_primary")])
            .fontSize(16)
            .margin({ right: 5 })
          Text("再看看教程?")
            .fontColor($r("sys.color.font_primary"))
            .fontSize(16)
        }
        Button('看看', { type: ButtonType.Normal, buttonStyle: ButtonStyleMode.EMPHASIZED, role: ButtonRole.NORMAL })
          .borderRadius(13)
          .onClick(() => {
            EventHelper.emitterPublish("home_close_sheet")
            HMRouterMgr.push({ pageUrl: 'HelpPage' })
          })
      }
      .height(49)
      .borderRadius(18)
      .alignItems(VerticalAlign.Center)
      .justifyContent(FlexAlign.SpaceBetween)
      .width('100%')
      .backgroundColor($r("sys.color.background_secondary"))
      .padding({
        left: 10,
        right: 5,
        top: 5,
        bottom: 5
      })
      .margin({ bottom: 10 })
    }
  }
  .width('100%')
  .height('100%')
  .scrollBar(BarState.Off)
  .padding({ left: 15, right: 15 })
}
