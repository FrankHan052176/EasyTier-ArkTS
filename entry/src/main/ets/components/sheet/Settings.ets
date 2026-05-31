import { AppManager } from '../../AppManager'
import { HMRouterMgr } from '@hadss/hmrouter'
import { APP_VERSION, APP_VERSION_CODE, BUILD_TIME, CORE_VERSION } from '../../util/info/BuildTime'
import { EditableLeftIconType, EditableTitleBar, LengthMetrics } from '@kit.ArkUI'
import { EventHelper } from '../../util/EventHelper'
import { deviceInfo } from '@kit.BasicServicesKit'
import { sendToast } from '../../ToastUtil'
import { cloudSync } from '@kit.CoreFileKit'

function formatSyncTime(raw: string): string {
  let value = Number.parseInt(raw, 10) || 0
  if (value <= 0) {
    return '未记录'
  }
  if (value < 1000000000000) {
    value *= 1000
  }
  const date = new Date(value)
  const yyyy = date.getFullYear()
  const mm = String(date.getMonth() + 1).padStart(2, '0')
  const dd = String(date.getDate()).padStart(2, '0')
  const hh = String(date.getHours()).padStart(2, '0')
  const mi = String(date.getMinutes()).padStart(2, '0')
  const ss = String(date.getSeconds()).padStart(2, '0')
  return `${yyyy}-${mm}-${dd} ${hh}:${mi}:${ss}`
}

function formatSyncState(state: cloudSync.SyncState): string {
  switch (state) {
    case cloudSync.SyncState.UPLOADING:
      return '上传中'
    case cloudSync.SyncState.UPLOAD_FAILED:
      return '上传失败'
    case cloudSync.SyncState.DOWNLOADING:
      return '下载中'
    case cloudSync.SyncState.DOWNLOAD_FAILED:
      return '下载失败'
    case cloudSync.SyncState.COMPLETED:
      return '已完成'
    case cloudSync.SyncState.STOPPED:
      return '已停止'
    default:
      return '未知状态'
  }
}

function formatSyncError(error: cloudSync.ErrorType): string {
  switch (error) {
    case cloudSync.ErrorType.NO_ERROR:
      return '无'
    case cloudSync.ErrorType.NETWORK_UNAVAILABLE:
      return '网络不可用'
    case cloudSync.ErrorType.WIFI_UNAVAILABLE:
      return 'Wi-Fi 不可用'
    case cloudSync.ErrorType.BATTERY_LEVEL_LOW:
      return '电量过低'
    case cloudSync.ErrorType.BATTERY_LEVEL_WARNING:
      return '电量告警'
    case cloudSync.ErrorType.CLOUD_STORAGE_FULL:
      return '云空间已满'
    case cloudSync.ErrorType.LOCAL_STORAGE_FULL:
      return '本地存储已满'
    case cloudSync.ErrorType.DEVICE_TEMPERATURE_TOO_HIGH:
      return '设备温度过高'
    case cloudSync.ErrorType.REMOTE_SERVER_ABNORMAL:
      return '云端服务异常'
    default:
      return `错误码 ${error}`
  }
}

function formatCacheState(state: cloudSync.State): string {
  switch (state) {
    case cloudSync.State.RUNNING:
      return '缓存中'
    case cloudSync.State.COMPLETED:
      return '缓存完成'
    case cloudSync.State.FAILED:
      return '缓存失败'
    case cloudSync.State.STOPPED:
      return '未缓存'
    default:
      return '未知状态'
  }
}

function formatCacheError(error: cloudSync.DownloadErrorType): string {
  switch (error) {
    case cloudSync.DownloadErrorType.NO_ERROR:
      return '无'
    default:
      return `错误码 ${error}`
  }
}

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
    ListItem()
      .height(64)
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
      .backgroundColor($r("sys.color.background_primary"))
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
          SymbolGlyph($r("sys.symbol.timer"))
            .fontColor([$r("sys.color.font_primary")])
            .fontSize(16)
            .margin({ right: 5 })
          Text("内核运行时长")
            .fontColor($r("sys.color.font_primary"))
            .fontSize(16)
        }

        Text(AppManager.runtimeStats.runtimeDurationText)
          .fontColor($r("sys.color.font_primary"))
          .fontSize(16)
          .margin({ right: 5 })
      }
      .height(49)
      .borderRadius(18)
      .alignItems(VerticalAlign.Center)
      .justifyContent(FlexAlign.SpaceBetween)
      .width('100%')
      .backgroundColor($r("sys.color.background_primary"))
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
          SymbolGlyph($r("sys.symbol.clock"))
            .fontColor([$r("sys.color.font_primary")])
            .fontSize(16)
            .margin({ right: 5 })
          Text("内核内存占用")
            .fontColor($r("sys.color.font_primary"))
            .fontSize(16)
        }

        Text(AppManager.runtimeStats.memoryUsageText)
          .fontColor($r("sys.color.font_primary"))
          .fontSize(16)
          .margin({ right: 5 })
      }
      .height(49)
      .borderRadius(18)
      .alignItems(VerticalAlign.Center)
      .justifyContent(FlexAlign.SpaceBetween)
      .width('100%')
      .backgroundColor($r("sys.color.background_primary"))
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
          SymbolGlyph($r("sys.symbol.house_fill"))
            .fontColor([$r("sys.color.font_primary")])
            .fontSize(16)
            .margin({ right: 5 })
          Text("子进程模式")
            .fontColor($r("sys.color.font_primary"))
            .fontSize(16)
            .margin({ right: 5 })
          if (AppManager.easytier.runningNetworks.size > 0) {
            Text("运行时禁止切换")
              .fontColor($r("sys.color.font_secondary"))
              .fontSize(14)
          }
        }

        Toggle({ type: ToggleType.Switch, isOn: AppManager.uiState.ext_mode })
          .selectedColor($r('sys.color.brand'))
          .switchPointColor($r('sys.color.comp_background_list_card'))
          .onChange((isOn: boolean) => {
            AppManager.uiState.ext_mode = isOn
          })
          .height(29)
          .width(52)
          .enabled(AppManager.easytier.runningNetworks.size == 0)
      }
      .height(49)
      .borderRadius(18)
      .alignItems(VerticalAlign.Center)
      .justifyContent(FlexAlign.SpaceBetween)
      .width('100%')
      .backgroundColor($r("sys.color.background_primary"))
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
      .backgroundColor($r("sys.color.background_primary"))
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
      .backgroundColor($r("sys.color.background_primary"))
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
      .backgroundColor($r("sys.color.background_primary"))
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
      .backgroundColor($r("sys.color.background_primary"))
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
        .backgroundColor($r("sys.color.background_primary"))
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
            Text("分享崩溃日志")
              .fontColor($r("sys.color.font_primary"))
              .fontSize(16)
          }
          Button('分享', { type: ButtonType.Normal, buttonStyle: ButtonStyleMode.EMPHASIZED, role: ButtonRole.NORMAL })
            .borderRadius(13)
            .onClick(() => {
              AppManager.easytier.writeAndShareCrashLog()
            })
        }
        .height(49)
        .borderRadius(18)
        .alignItems(VerticalAlign.Center)
        .justifyContent(FlexAlign.SpaceBetween)
        .width('100%')
        .backgroundColor($r("sys.color.background_primary"))
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
        .backgroundColor($r("sys.color.background_primary"))
        .padding({
          left: 10,
          right: 5,
          top: 5,
          bottom: 5
        })
      }
      .margin({ bottom: 10 })

      ListItem() {
          Column({ space: 10 }) {
            Row() {
              Row() {
                SymbolGlyph($r("sys.symbol.doc"))
                  .fontColor([$r("sys.color.font_primary")])
                  .fontSize(16)
                  .margin({ right: 5 })
                Text("配置同步到云空间")
                  .fontColor($r("sys.color.font_primary"))
                  .fontSize(16)
              }
              Toggle({ type: ToggleType.Switch, isOn: AppManager.uiState.cloud_auto_sync })
                .selectedColor($r('sys.color.brand'))
                .switchPointColor($r('sys.color.comp_background_list_card'))
                .onChange((isOn: boolean) => {
                  AppManager.uiState.cloud_auto_sync = isOn
                  AppManager.cloudSync.onAutoSyncChanged(isOn)
                })
                .height(29)
                .width(52)
            }
            .height(49)
            .alignItems(VerticalAlign.Center)
            .justifyContent(FlexAlign.SpaceBetween)
            .width('100%')

            Row({space: 8}) {
              Row() {
                Text(`本地变更：`)
                  .fontSize(12)
                  .fontColor($r("sys.color.font_secondary"))
                Text(`${formatSyncTime(AppManager.cloudSync.localUpdatedAt)}`)
                  .fontSize(12)
                  .fontColor($r("sys.color.font_secondary"))
                  .layoutWeight(1)
                  .textAlign(TextAlign.End)
              }
              .layoutWeight(1)
              Row() {
                Text(`云端变更：`)
                  .fontSize(12)
                  .fontColor($r("sys.color.font_secondary"))
                  .textAlign(TextAlign.End)
                Text(`${formatSyncTime(AppManager.cloudSync.cloudUpdatedAt)}`)
                  .fontSize(12)
                  .fontColor($r("sys.color.font_secondary"))
                  .textAlign(TextAlign.End)
                  .layoutWeight(1)
              }
              .layoutWeight(1)
              .align(Alignment.End)
            }
            .width('100%')

            Text(`同步状态：${formatSyncState(AppManager.cloudSync.syncState)}`)
              .fontSize(12)
              .fontColor($r("sys.color.font_secondary"))

            Text(`缓存状态：${formatCacheState(AppManager.cloudSync.cacheState)}${AppManager.cloudSync.cacheState === cloudSync.State.RUNNING ? ` (${AppManager.cloudSync.cacheProgress}%)` : ''}`)
              .fontSize(12)
              .fontColor($r("sys.color.font_secondary"))

            if (AppManager.cloudSync.syncError !== cloudSync.ErrorType.NO_ERROR) {
              Text(`同步异常：${formatSyncError(AppManager.cloudSync.syncError)}`)
                .fontSize(12)
                .fontColor($r("sys.color.font_secondary"))
            }

            if (AppManager.cloudSync.cacheError !== cloudSync.DownloadErrorType.NO_ERROR) {
              Text(`缓存异常：${formatCacheError(AppManager.cloudSync.cacheError)}`)
                .fontSize(12)
                .fontColor($r("sys.color.font_secondary"))
            }

            Text(`最近结果：${AppManager.cloudSync.lastSyncMessage}`)
              .fontSize(12)
              .fontColor($r("sys.color.font_secondary"))

            Row({ space: 8 }) {
              Button('上传', { type: ButtonType.Normal, buttonStyle: ButtonStyleMode.EMPHASIZED, role: ButtonRole.NORMAL })
                .layoutWeight(1)
                .borderRadius(13)
                .onClick(() => {
                  AppManager.cloudSync.uploadToCloud().catch(() => {
                    sendToast('上传配置到云端失败', $r("sys.symbol.exclamationmark_circle"), 1)
                  })
                })
              Button('更新', { type: ButtonType.Normal, buttonStyle: ButtonStyleMode.NORMAL, role: ButtonRole.NORMAL })
                .layoutWeight(1)
                .borderRadius(13)
                .onClick(() => {
                  AppManager.cloudSync.updateFromCloud().catch(() => {
                    sendToast('从云端更新配置失败', $r("sys.symbol.exclamationmark_circle"), 1)
                  })
                })
            }
            .width('100%')

            Button('全部重置', { type: ButtonType.Normal, buttonStyle: ButtonStyleMode.NORMAL, role: ButtonRole.ERROR })
              .width('100%')
              .borderRadius(13)
              .onClick(() => {
                AppManager.cloudSync.resetAllSyncData().catch(() => {
                  sendToast('重置本地与云端数据失败', $r("sys.symbol.exclamationmark_circle"), 1)
                })
              })
          }
          .width('100%')
          .padding({ left: 10, right: 10, top: 0, bottom: 10 })
          .borderRadius(18)
          .backgroundColor($r("sys.color.background_primary"))
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
          .backgroundColor($r("sys.color.background_primary"))
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
        .backgroundColor($r("sys.color.background_primary"))
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
          .backgroundColor($r("sys.color.background_primary"))
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
          .backgroundColor($r("sys.color.background_primary"))
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
        .backgroundColor($r("sys.color.background_primary"))
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
        .backgroundColor($r("sys.color.background_primary"))
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
      .backgroundColor($r("sys.color.background_primary"))
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
      .backgroundColor($r("sys.color.background_primary"))
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
