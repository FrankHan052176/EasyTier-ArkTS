import { AppManager } from '../../AppManager'
import { HMRouterMgr } from '@hadss/hmrouter'
import { APP_VERSION, APP_VERSION_CODE, BUILD_TIME, CORE_VERSION } from '../../util/info/BuildTime'
import { EventHelper } from '../../util/EventHelper'
import { deviceInfo } from '@kit.BasicServicesKit'
import { sendToast } from '../../ToastUtil'
import { cloudSync } from '@kit.CoreFileKit'
import { common } from '@kit.AbilityKit'

const CORE_REPOSITORY_URL = 'https://github.com/EasyTier/EasyTier'
const SHELL_REPOSITORY_URL =
  'https://codehub.devcloud.cn-north-4.huaweicloud.com/4514d04878fd4a568dd13915e0b0cfd0/EasyTier.git'
const EDGEONE_URL = 'https://edgeone.ai/?from=github'
const LANGLANG_URL = 'https://langlangy.cn/?i26c5a5'
const RAINCLOUD_URL = 'https://www.rainyun.com/NjM0NzQ1_'

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

@Builder
function settingGroupHeader(title: string) {
  Text(title)
    .width('100%')
    .fontSize(14)
    .fontColor($r("sys.color.font_secondary"))
    .padding({ top: 10, left: 5, bottom: 3 })
}

function boolText(value: boolean): string {
  return value ? '开启' : '关闭'
}

function permissionSummary(): string {
  let count = 0
  if (AppManager.permission.isGetLocPerm()) {
    count++
  }
  if (AppManager.permission.isGetDistributePerm()) {
    count++
  }
  if (AppManager.permission.isGetNotificationPerm()) {
    count++
  }
  return `${count}/3 已授权`
}

function appCoreVersionSummary(): string {
  return `${APP_VERSION}&${CORE_VERSION}`
}

function openLinkUrl(url: string): void {
  if (!AppManager.content.context) {
    sendToast('打开链接失败', $r("sys.symbol.exclamationmark_circle"), 1)
    return
  }
  (AppManager.content.context as common.UIAbilityContext).openLink(url).catch(() => {
    sendToast('打开链接失败', $r("sys.symbol.exclamationmark_circle"), 1)
  })
}

@Builder
function settingMenuRow(symbol: Resource, title: string, subtitle: string, onClick: () => void) {
  ListItem() {
    Row() {
      Row() {
        SymbolGlyph(symbol)
          .fontColor([$r("sys.color.font_primary")])
          .fontSize(16)
          .margin({ right: 8 })
        if (subtitle.length > 0) {
          Column() {
            Text(title)
              .fontColor($r("sys.color.font_primary"))
              .fontSize(16)
              .maxLines(1)
            Text(subtitle)
              .fontColor($r("sys.color.font_secondary"))
              .fontSize(12)
              .maxLines(1)
              .margin({ top: 3 })
          }
          .alignItems(HorizontalAlign.Start)
        } else {
          Text(title)
            .fontColor($r("sys.color.font_primary"))
            .fontSize(16)
            .maxLines(1)
        }
      }
      .layoutWeight(1)

      SymbolGlyph($r("sys.symbol.arrow_right"))
        .fontColor([$r("sys.color.font_primary")])
        .fontSize(16)
        .margin({ left: 8, right: 5 })
    }
    .height(subtitle.length > 0 ? 58 : 49)
    .borderRadius(18)
    .alignItems(VerticalAlign.Center)
    .justifyContent(FlexAlign.SpaceBetween)
    .width('100%')
    .backgroundColor($r("sys.color.comp_background_primary"))
    .shadow({
      radius: 7,
      color: '#1F000000'
    })
    .padding({
      left: 10,
      right: 5,
      top: 5,
      bottom: 5
    })
    .clickEffect({
      level: ClickEffectLevel.LIGHT
    })
    .onClick(onClick)
  }
  .margin({ bottom: 10 })
}

@Builder
function settingValueRow(symbol: Resource, title: string, value: string) {
  ListItem() {
    Row() {
      Row() {
        SymbolGlyph(symbol)
          .fontColor([$r("sys.color.font_primary")])
          .fontSize(16)
          .margin({ right: 5 })
        Text(title)
          .fontColor($r("sys.color.font_primary"))
          .fontSize(16)
      }

      Text(value)
        .fontColor($r("sys.color.font_primary"))
        .fontSize(16)
        .margin({ right: 5 })
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .height(49)
    .borderRadius(18)
    .alignItems(VerticalAlign.Center)
    .justifyContent(FlexAlign.SpaceBetween)
    .width('100%')
    .backgroundColor($r("sys.color.comp_background_primary"))
    .shadow({
      radius: 7,
      color: '#1F000000'
    })
    .padding({
      left: 10,
      right: 5,
      top: 5,
      bottom: 5
    })
  }
  .margin({ bottom: 10 })
}

@Builder
function settingSwitchRow(symbol: Resource, title: string, hint: string, isOn: boolean, enabled: boolean,
  onChange: (isOn: boolean) => void) {
  ListItem() {
    Row() {
      Row() {
        SymbolGlyph(symbol)
          .fontColor([$r("sys.color.font_primary")])
          .fontSize(16)
          .margin({ right: 5 })
        Text(title)
          .fontColor($r("sys.color.font_primary"))
          .fontSize(16)
          .margin({ right: 5 })
        if (hint.length > 0) {
          Text(hint)
            .fontColor($r("sys.color.font_secondary"))
            .fontSize(14)
            .maxLines(1)
        }
      }
      .layoutWeight(1)

      Toggle({ type: ToggleType.Switch, isOn: isOn })
        .selectedColor($r('sys.color.brand'))
        .switchPointColor($r('sys.color.comp_background_list_card'))
        .onChange(onChange)
        .height(29)
        .width(52)
        .enabled(enabled)
    }
    .height(49)
    .borderRadius(18)
    .alignItems(VerticalAlign.Center)
    .justifyContent(FlexAlign.SpaceBetween)
    .width('100%')
    .backgroundColor($r("sys.color.comp_background_primary"))
    .shadow({
      radius: 7,
      color: '#1F000000'
    })
    .padding(10)
  }
  .margin({ bottom: 10 })
}

@Builder
function settingButtonRow(symbol: Resource, title: string, buttonText: string, onClick: () => void) {
  ListItem() {
    Row() {
      Row() {
        SymbolGlyph(symbol)
          .fontColor([$r("sys.color.font_primary")])
          .fontSize(16)
          .margin({ right: 5 })
        Text(title)
          .fontColor($r("sys.color.font_primary"))
          .fontSize(16)
      }

      Button(buttonText, { type: ButtonType.Normal, buttonStyle: ButtonStyleMode.EMPHASIZED, role: ButtonRole.NORMAL })
        .borderRadius(13)
        .onClick(onClick)
    }
    .height(49)
    .borderRadius(18)
    .alignItems(VerticalAlign.Center)
    .justifyContent(FlexAlign.SpaceBetween)
    .width('100%')
    .backgroundColor($r("sys.color.comp_background_primary"))
    .shadow({
      radius: 7,
      color: '#1F000000'
    })
    .padding({
      left: 10,
      right: 5,
      top: 5,
      bottom: 5
    })
  }
  .margin({ bottom: 10 })
}

@Builder
function settingSponsorRow(symbol: Resource, title: string, subtitle: string, url: string) {
  ListItem() {
    Row() {
      Row() {
        SymbolGlyph(symbol)
          .fontColor([$r("sys.color.font_primary")])
          .fontSize(16)
          .margin({ right: 5 })
        Column() {
          Text(title)
            .fontColor($r("sys.color.font_primary"))
            .fontSize(16)
            .maxLines(1)
          Text(subtitle)
            .fontColor($r("sys.color.font_secondary"))
            .fontSize(12)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .margin({ top: 3 })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
      }
      .layoutWeight(1)

      Button('打开', { type: ButtonType.Normal, buttonStyle: ButtonStyleMode.EMPHASIZED, role: ButtonRole.NORMAL })
        .borderRadius(13)
        .onClick(() => {
          openLinkUrl(url)
        })
    }
    .height(58)
    .borderRadius(18)
    .alignItems(VerticalAlign.Center)
    .justifyContent(FlexAlign.SpaceBetween)
    .width('100%')
    .backgroundColor($r("sys.color.comp_background_primary"))
    .shadow({
      radius: 7,
      color: '#1F000000'
    })
    .padding({
      left: 10,
      right: 5,
      top: 5,
      bottom: 5
    })
  }
  .margin({ bottom: 10 })
}

@Builder
function settingSponsorQrImage(source: Resource, title: string) {
  Column({ space: 6 }) {
    Image(source)
      .width('100%')
      .aspectRatio(0.826)
      .objectFit(ImageFit.Contain)
      .backgroundColor(Color.White)
      .borderRadius(10)
      .padding(6)
    Text(title)
      .fontColor($r("sys.color.font_secondary"))
      .fontSize(12)
      .maxLines(1)
  }
  .layoutWeight(1)
  .alignItems(HorizontalAlign.Center)
}

@Builder
function settingSponsorQrCard() {
  ListItem() {
    Column({ space: 10 }) {
      Row() {
        SymbolGlyph($r("sys.symbol.doc"))
          .fontColor([$r("sys.color.font_primary")])
          .fontSize(16)
          .margin({ right: 5 })
        Column() {
          Text("源项目作者赞助")
            .fontColor($r("sys.color.font_primary"))
            .fontSize(16)
            .maxLines(1)
          Text("微信与支付宝收款码")
            .fontColor($r("sys.color.font_secondary"))
            .fontSize(12)
            .maxLines(1)
            .margin({ top: 3 })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Row({ space: 10 }) {
        settingSponsorQrImage($r("app.media.wechat"), "微信")
        settingSponsorQrImage($r("app.media.alipay"), "支付宝")
      }
      .width('100%')
    }
    .borderRadius(18)
    .width('100%')
    .backgroundColor($r("sys.color.comp_background_primary"))
    .shadow({
      radius: 7,
      color: '#1F000000'
    })
    .padding({
      left: 10,
      right: 10,
      top: 10,
      bottom: 10
    })
  }
  .margin({ bottom: 10 })
}

@Builder
function SettingHome_Sheet(onNavigate: (page: string) => void) {
  List() {
    ListItem()
      .height(64)

    ListItemGroup({ header: settingGroupHeader("常用") }) {
      settingMenuRow($r("sys.symbol.disconnect"), "UI 设置", "布局、握持姿态与主页模块", () => {
        onNavigate('ui')
      })
      settingMenuRow($r("sys.symbol.list_xmark"), AppManager.uiState.white_list ? "App 白名单" : "App 黑名单",
        "控制 App 过滤列表", () => {
          onNavigate('black_list')
        })
    }

    ListItemGroup({ header: settingGroupHeader("运行") }) {
      settingValueRow($r("sys.symbol.timer"), "内核运行时长", AppManager.runtimeStats.runtimeDurationText)
      settingValueRow($r("sys.symbol.clock"), "内核内存占用", AppManager.runtimeStats.memoryUsageText)
      settingSwitchRow($r("sys.symbol.house_fill"), "子进程模式",
        AppManager.easytier.runningNetworks.size > 0 ? "运行时禁止切换" : "",
        AppManager.uiState.ext_mode, AppManager.easytier.runningNetworks.size == 0, (isOn: boolean) => {
          AppManager.uiState.ext_mode = isOn
        })
      settingMenuRow($r("sys.symbol.cloud"), "云空间同步", formatSyncState(AppManager.cloudSync.syncState), () => {
        onNavigate('cloud_sync')
      })
      settingMenuRow($r("sys.symbol.doc"), "日志与调试",
        `内核日志${boolText(AppManager.uiState.core_log)}，调试日志${boolText(AppManager.uiState.debug_log)}`, () => {
          onNavigate('logs')
        })
    }

    ListItemGroup({ header: settingGroupHeader("系统") }) {
      settingMenuRow($r("sys.symbol.local_and_rectangle"), "权限", permissionSummary(), () => {
        onNavigate('permissions')
      })
      settingMenuRow($r("sys.symbol.person"), "高级设置", "路由表、DNS 与高级选项", () => {
        onNavigate('advanced')
      })
      settingMenuRow($r("sys.symbol.info_circle"), "关于与帮助", appCoreVersionSummary(), () => {
        onNavigate('about')
      })
    }

    ListItem()
      .height(100)
  }
  .width('100%')
  .height('100%')
  .scrollBar(BarState.Off)
  .padding({ left: 15, right: 15 })
}

@Builder
export function SettingLogs_Content() {
  List() {
    ListItem()
      .height(64)

    ListItemGroup({ header: settingGroupHeader("记录") }) {
      settingSwitchRow($r("sys.symbol.exclamationmark_message_middle_bottom"), "记录内核日志",
        AppManager.uiState.inittedCoreLog != AppManager.uiState.core_log ? "重启后生效" : "",
        AppManager.uiState.core_log, true, (isOn: boolean) => {
          AppManager.uiState.core_log = isOn
        })
      settingSwitchRow($r("sys.symbol.doc"), "记录调试日志", "",
        AppManager.uiState.debug_log, true, (isOn: boolean) => {
          AppManager.uiState.debug_log = isOn
        })
    }

    ListItemGroup({ header: settingGroupHeader("分享") }) {
      settingButtonRow($r("sys.symbol.doc"), "分享崩溃日志", "分享", () => {
        AppManager.easytier.writeAndShareCrashLog()
      })
      settingButtonRow($r("sys.symbol.doc"), "分享日志", "分享", () => {
        AppManager.easytier.writeAndShareLogs()
      })
    }
  }
  .width('100%')
  .height('100%')
  .scrollBar(BarState.Off)
  .padding({ left: 15, right: 15 })
}

@Builder
export function SettingCloudSync_Content() {
  List() {
    ListItem()
      .height(64)

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

        Row({ space: 8 }) {
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

        Text(`缓存状态：${formatCacheState(AppManager.cloudSync.cacheState)}${AppManager.cloudSync.cacheState ===
          cloudSync.State.RUNNING ? ` (${AppManager.cloudSync.cacheProgress}%)` : ''}`)
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
      .padding({
        left: 10,
        right: 10,
        top: 0,
        bottom: 10
      })
      .borderRadius(18)
      .backgroundColor($r("sys.color.comp_background_primary"))
      .shadow({
        radius: 7,
        color: '#1F000000'
      })
    }
    .margin({ bottom: 10 })
  }
  .width('100%')
  .height('100%')
  .scrollBar(BarState.Off)
  .padding({ left: 15, right: 15 })
}

@ComponentV2
export struct SettingAdvanced_Content {
  @Local advancedMode: boolean = AppManager.uiState.dev
  @Local vpnRoutes: boolean = AppManager.uiState.vpn_routes
  @Local forceGlobal: boolean = AppManager.uiState.force_global

  build() {
    List() {
      ListItem()
        .height(64)

      ListItemGroup({ header: settingGroupHeader("高级") }) {
        if (deviceInfo.sdkApiVersion < 20) {
          settingSwitchRow($r("sys.symbol.list_square_bill"), "路由表模式", "",
            this.vpnRoutes, true, (isOn: boolean) => {
              this.vpnRoutes = isOn
              AppManager.uiState.vpn_routes = isOn
            })
        }
        settingSwitchRow($r("sys.symbol.person"), "高级模式", "",
          this.advancedMode, true, (isOn: boolean) => {
            this.advancedMode = isOn
            AppManager.uiState.dev = isOn
          })

        if (this.advancedMode) {
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
                  } else {
                    AppManager.uiState.dns = "223.5.5.5"
                  }
                })
            }
            .height(49)
            .borderRadius(18)
            .alignItems(VerticalAlign.Center)
            .justifyContent(FlexAlign.SpaceBetween)
            .width('100%')
            .backgroundColor($r("sys.color.comp_background_primary"))
            .shadow({
              radius: 7,
              color: '#1F000000'
            })
            .padding({ left: 10, right: 10 })
          }
          .margin({ bottom: 10 })

          settingSwitchRow($r("sys.symbol.person"), "添加全局路由", "",
            this.forceGlobal, true, (isOn: boolean) => {
              this.forceGlobal = isOn
              AppManager.uiState.force_global = isOn
            })
        }
      }
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Off)
    .padding({ left: 15, right: 15 })
  }
}

@Builder
export function SettingPermissions_Content() {
  List() {
    ListItem()
      .height(64)

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
        .backgroundColor($r("sys.color.comp_background_primary"))
        .shadow({
          radius: 7,
          color: '#1F000000'
        })
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
        .backgroundColor($r("sys.color.comp_background_primary"))
        .shadow({
          radius: 7,
          color: '#1F000000'
        })
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
        .backgroundColor($r("sys.color.comp_background_primary"))
        .shadow({
          radius: 7,
          color: '#1F000000'
        })
        .padding({
          left: 10,
          right: 5,
          top: 5,
          bottom: 5
        })
      }
      .margin({ bottom: 10 })
    }
  }
  .width('100%')
  .height('100%')
  .scrollBar(BarState.Off)
  .padding({ left: 15, right: 15 })
}

@Builder
export function SettingAbout_Content() {
  List() {
    ListItem()
      .height(64)

    ListItemGroup({ header: settingGroupHeader("版本") }) {
      settingValueRow($r("sys.symbol.square_fill_grid_2x2"), "APP版本", APP_VERSION + "(" + APP_VERSION_CODE + ")")
      settingValueRow($r("sys.symbol.square_fill_grid_2x2"), "编译时间", BUILD_TIME)
      settingValueRow($r("sys.symbol.house"), "内核版本", CORE_VERSION)
    }

    ListItemGroup({ header: settingGroupHeader("帮助") }) {
      settingButtonRow($r("sys.symbol.questionmark_circle"), "再看看教程?", "看看", () => {
        EventHelper.emitterPublish("home_close_sheet")
        HMRouterMgr.push({ pageUrl: 'HelpPage' })
      })
    }

    ListItemGroup({ header: settingGroupHeader("仓库") }) {
      settingButtonRow($r("sys.symbol.house"), "内核仓库", "打开", () => {
        openLinkUrl(CORE_REPOSITORY_URL)
      })
      settingButtonRow($r("sys.symbol.disconnect"), "鸿蒙壳仓库", "打开", () => {
        openLinkUrl(SHELL_REPOSITORY_URL)
      })
    }

    ListItemGroup({ header: settingGroupHeader("赞助者") }) {
      settingSponsorRow($r("sys.symbol.cloud"), "腾讯 EdgeOne", "CDN 加速和安全防护赞助", EDGEONE_URL)
      settingSponsorRow($r("sys.symbol.house"), "浪浪云", "公共服务器赞助", LANGLANG_URL)
      settingSponsorRow($r("sys.symbol.cloud"), "雨云", "公共服务器赞助", RAINCLOUD_URL)
      settingSponsorQrCard()
    }

    ListItem().height(100)
  }
  .width('100%')
  .height('100%')
  .scrollBar(BarState.Off)
  .padding({ left: 15, right: 15 })
}

@Builder
export function Setting_Sheet(onNavigate: (page: string) => void) {
  SettingHome_Sheet(onNavigate)
}
