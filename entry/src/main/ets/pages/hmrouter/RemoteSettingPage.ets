import { HMRouter, HMRouterMgr } from '@hadss/hmrouter'
import { HdsNavigation, HdsNavigationTitleMode, hdsMaterial, TitleBarStyleOptions } from '@kit.UIDesignKit'
import { LengthMetrics } from '@kit.ArkUI'
import { deviceInfo } from '@kit.BasicServicesKit'
import { HdsMenuButton } from '../Components'
import { RemoteSettingPageParam } from '../../types/navigation/PageParam'
import { RemoteManageService } from '../../services/remote/RemoteManageService'
import { RemoteSettingsState, RemoteSummary } from '../../services/remote/RemoteManageTypes'
import { sendToast } from '../../ToastUtil'
import {
  RuntimeModeSelectOption,
  runtimeModeFromSettings,
  runtimeModeOptions,
  runtimeModeText
} from '../../types/runtime/RuntimeModeTypes'

function remoteSettingTitleStyle(): TitleBarStyleOptions {
  if (deviceInfo.distributionOSApiVersion >= 60100 && hdsMaterial.getSystemMaterialTypes().length > 0) {
    return {
      scrollEffectOpts: {
        enableScrollEffect: true,
        scrollEffectType: deviceInfo.sdkApiVersion >= 23 ? 3 : 2,
        blurEffectiveStartOffset: LengthMetrics.vp(0),
        blurEffectiveEndOffset: LengthMetrics.vp(20),
      },
      originalStyle: {
        contentStyle: {
          titleStyle: {
            mainTitleColor: $r('sys.color.font_primary'),
            subTitleColor: $r('sys.color.font_secondary')
          },
          menuStyle: {
            iconColor: $r('sys.color.font_primary')
          },
          backIconStyle: {
            iconColor: $r('sys.color.font_primary')
          }
        }
      },
      systemMaterialEffect: {
        materialType: hdsMaterial.MaterialType.ADAPTIVE,
        materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
      }
    }
  }
  return {
    scrollEffectOpts: {
      enableScrollEffect: true,
      scrollEffectType: deviceInfo.sdkApiVersion >= 23 ? 3 : 2,
      blurEffectiveStartOffset: LengthMetrics.vp(0),
      blurEffectiveEndOffset: LengthMetrics.vp(20),
    },
    originalStyle: {
      contentStyle: {
        titleStyle: {
          mainTitleColor: $r('sys.color.font_primary'),
          subTitleColor: $r('sys.color.font_secondary')
        },
        menuStyle: {
          iconColor: $r('sys.color.font_primary'),
          backgroundColor: $r('sys.color.background_primary')
        },
        backIconStyle: {
          iconColor: $r('sys.color.font_primary'),
          backgroundColor: $r('sys.color.background_primary')
        }
      }
    }
  }
}

@Builder
function remoteSettingHeader(title: string) {
  Text(title)
    .width('100%')
    .fontSize(14)
    .fontColor($r('sys.color.font_secondary'))
    .padding({ top: 10, left: 5, bottom: 3 })
}

@Builder
function remoteValueRow(title: string, value: string) {
  ListItem() {
    Row() {
      Text(title)
        .fontColor($r('sys.color.font_primary'))
        .fontSize(16)
      Text(value)
        .fontColor($r('sys.color.font_primary'))
        .fontSize(16)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .height(49)
    .borderRadius(18)
    .alignItems(VerticalAlign.Center)
    .justifyContent(FlexAlign.SpaceBetween)
    .width('100%')
    .backgroundColor($r('sys.color.comp_background_primary'))
    .shadow({
      radius: 7,
      color: '#1F000000'
    })
    .padding({ left: 12, right: 12 })
  }
  .margin({ bottom: 10 })
}

interface RemoteSelectOption {
  value: string
}

class RemoteSelectOptionItem implements RemoteSelectOption {
  value: string

  constructor(value: string) {
    this.value = value
  }
}

@ComponentV2
struct RemoteRuntimeSelector {
  @Param @Require options: RuntimeModeSelectOption[]
  @Param @Require selected: string
  @Param canSelect: boolean = true
  @Event onChange: (value: string) => void = () => {}
  private readonly selectorWidth: number = 136

  @Computed
  get selectedIndex(): number {
    const index = this.options.findIndex((option: RuntimeModeSelectOption) => {
      return option.value === this.selected
    })
    return index >= 0 ? index : 0
  }

  @Computed
  get selectOptions(): RemoteSelectOption[] {
    return this.options.map((option: RuntimeModeSelectOption) => {
      return new RemoteSelectOptionItem(option.label)
    })
  }

  build() {
    Select(this.selectOptions)
      .selected(this.selectedIndex)
      .value(runtimeModeText(this.selected))
      .width(this.selectorWidth)
      .height(40)
      .controlSize(ControlSize.SMALL)
      .font({ size: 14, weight: FontWeight.Medium })
      .fontColor($r('sys.color.font_primary'))
      .selectedOptionBgColor($r('sys.color.brand'))
      .selectedOptionFontColor('#FFFFFFFF')
      .optionBgColor($r('sys.color.comp_background_primary'))
      .optionFont({ size: 14, weight: FontWeight.Medium })
      .optionFontColor($r('sys.color.font_primary'))
      .optionWidth(this.selectorWidth)
      .menuBackgroundColor($r('sys.color.comp_background_primary'))
      .borderRadius(14)
      .opacity(this.canSelect ? 1 : 0.55)
      .enabled(this.canSelect)
      .onSelect((index: number) => {
        if (!this.canSelect || index < 0 || index >= this.options.length) {
          return
        }
        this.onChange(this.options[index].value)
      })
  }
}

function isRemoteSettingCategory(category: string): boolean {
  return category === 'runtime' || category === 'advanced' || category === 'logs' || category === 'permissions'
}

@HMRouter({ pageUrl: 'RemoteSettingPage' })
@ComponentV2
export struct RemoteSettingPage {
  @Local category: string = ''
  @Local title: string = '远端设置'
  @Local summary: RemoteSummary | undefined = RemoteManageService.cachedSummary
  @Local settings: RemoteSettingsState | undefined = RemoteManageService.cachedSummary?.settings
  @Local remoteSessionId: string = ''
  @Local remoteDeviceName: string = ''

  aboutToAppear(): void {
    const param = HMRouterMgr.getCurrentParam() as RemoteSettingPageParam
    this.category = param.category
    this.title = param.title
    if (!isRemoteSettingCategory(this.category)) {
      sendToast('不支持的远端设置分类', $r('sys.symbol.exclamationmark_circle'), 1)
      setTimeout(() => {
        HMRouterMgr.pop()
      }, 0)
      return
    }
    this.remoteSessionId = param.remoteSessionId ?? RemoteManageService.currentSessionKey ?? ''
    this.remoteDeviceName = param.remoteDeviceName ?? RemoteManageService.currentDeviceName
    if (!RemoteManageService.isCurrentSession(this.remoteSessionId)) {
      sendToast('远端连接已变化，请重新进入设置', $r('sys.symbol.exclamationmark_circle'), 1)
      setTimeout(() => {
        HMRouterMgr.pop()
      }, 0)
      return
    }
    this.refresh()
  }

  private async refresh(): Promise<void> {
    if (!RemoteManageService.isCurrentSession(this.remoteSessionId)) {
      sendToast('远端未连接', $r('sys.symbol.exclamationmark_circle'), 1)
      return
    }
    try {
      this.summary = await RemoteManageService.requestSummary(this.remoteSessionId)
      this.settings = this.summary.settings
    } catch (_) {
      sendToast('读取远端设置失败', $r('sys.symbol.exclamationmark_circle'), 1)
    }
  }

  private async setSwitch(key: string, value: boolean): Promise<void> {
    try {
      this.settings = await RemoteManageService.setSetting(key, value, this.remoteSessionId)
      if (this.summary) {
        this.summary.settings = this.settings
      }
    } catch (_) {
      sendToast('同步远端设置失败', $r('sys.symbol.exclamationmark_circle'), 1)
    }
  }

  private async setText(key: string, value: string): Promise<void> {
    try {
      this.settings = await RemoteManageService.setSetting(key, value, this.remoteSessionId)
      if (this.summary) {
        this.summary.settings = this.settings
      }
    } catch (_) {
      sendToast('同步远端设置失败', $r('sys.symbol.exclamationmark_circle'), 1)
    }
  }

  private async setRuntimeMode(value: string): Promise<void> {
    try {
      this.settings = await RemoteManageService.setSetting('runtime_mode', value, this.remoteSessionId)
      if (this.summary) {
        this.summary.settings = this.settings
      }
    } catch (_) {
      sendToast('同步远端运行方案失败', $r('sys.symbol.exclamationmark_circle'), 1)
    }
  }

  private runtimeModeValue(): string {
    return runtimeModeFromSettings(this.settings?.background_keep_alive_mode)
  }

  private async requestPermission(kind: string): Promise<void> {
    try {
      this.settings = await RemoteManageService.requestPermission(kind, this.remoteSessionId)
      if (this.summary) {
        this.summary.settings = this.settings
      }
    } catch (_) {
      sendToast('请求远端权限失败', $r('sys.symbol.exclamationmark_circle'), 1)
    }
  }

  @Builder
  private switchRow(title: string, hint: string, key: string, value: boolean, enabled: boolean = true) {
    ListItem() {
      Row() {
        Column() {
          Text(title)
            .fontColor($r('sys.color.font_primary'))
            .fontSize(16)
          if (hint.length > 0) {
            Text(hint)
              .fontColor($r('sys.color.font_secondary'))
              .fontSize(12)
              .margin({ top: 3 })
          }
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        Toggle({ type: ToggleType.Switch, isOn: value })
          .selectedColor($r('sys.color.brand'))
          .switchPointColor($r('sys.color.comp_background_list_card'))
          .height(29)
          .width(52)
          .enabled(enabled)
          .onChange((isOn: boolean) => this.setSwitch(key, isOn))
      }
      .height(hint.length > 0 ? 58 : 49)
      .borderRadius(18)
      .alignItems(VerticalAlign.Center)
      .justifyContent(FlexAlign.SpaceBetween)
      .width('100%')
      .backgroundColor($r('sys.color.comp_background_primary'))
      .shadow({
        radius: 7,
        color: '#1F000000'
      })
      .padding({ left: 12, right: 12 })
    }
    .margin({ bottom: 10 })
  }

  @Builder
  private permissionRow(title: string, value: boolean, kind: string) {
    ListItem() {
      Row() {
        Text(title)
          .fontColor($r('sys.color.font_primary'))
          .fontSize(16)
        if (value) {
          Text('已授权')
            .fontColor($r('sys.color.font_primary'))
            .fontSize(16)
        } else {
          Button('授权', { type: ButtonType.Normal, buttonStyle: ButtonStyleMode.EMPHASIZED, role: ButtonRole.NORMAL })
            .borderRadius(13)
            .onClick(() => this.requestPermission(kind))
        }
      }
      .height(49)
      .borderRadius(18)
      .alignItems(VerticalAlign.Center)
      .justifyContent(FlexAlign.SpaceBetween)
      .width('100%')
      .backgroundColor($r('sys.color.comp_background_primary'))
      .shadow({
        radius: 7,
        color: '#1F000000'
      })
      .padding({ left: 12, right: 8 })
    }
    .margin({ bottom: 10 })
  }

  @Builder
  private runtimeSelectorRow(title: string, hint: string, selected: string, enabled: boolean) {
    ListItem() {
      Row() {
        Column() {
          Text(title)
            .fontColor($r('sys.color.font_primary'))
            .fontSize(16)
            .maxLines(1)
          Text(hint.length > 0 ? hint : '数据传输或音乐')
            .fontColor($r('sys.color.font_secondary'))
            .fontSize(12)
            .maxLines(1)
            .margin({ top: 3 })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        RemoteRuntimeSelector({
          options: runtimeModeOptions(),
          selected: selected,
          canSelect: enabled,
          onChange: (value: string) => {
            this.setRuntimeMode(value)
          }
        })
      }
      .height(58)
      .borderRadius(18)
      .alignItems(VerticalAlign.Center)
      .justifyContent(FlexAlign.SpaceBetween)
      .width('100%')
      .backgroundColor($r('sys.color.comp_background_primary'))
      .shadow({
        radius: 7,
        color: '#1F000000'
      })
      .padding({ left: 12, right: 12 })
    }
    .margin({ bottom: 10 })
  }

  @Builder
  private runtimeContent() {
    ListItemGroup({ header: remoteSettingHeader('运行') }) {
      remoteValueRow('配置数量', `${this.summary?.runtime.configCount ?? 0}`)
      remoteValueRow('运行配置', `${this.summary?.runtime.runningCount ?? 0}`)
      remoteValueRow('运行时长', this.summary?.runtime.runtimeDurationText ?? '未运行')
      remoteValueRow('内存占用', this.summary?.runtime.memoryUsageText ?? '未记录')
      this.runtimeSelectorRow('运行方案',
        (this.summary?.runtime.runningCount ?? 0) > 0 ? '运行时禁止切换' : '',
        this.runtimeModeValue(),
        (this.summary?.runtime.runningCount ?? 0) === 0)
    }
  }

  @Builder
  private advancedContent() {
    ListItemGroup({ header: remoteSettingHeader('网络高级') }) {
      if ((this.summary?.sdkApiVersion ?? deviceInfo.sdkApiVersion) < 20) {
        this.switchRow('路由表模式', '', 'vpn_routes', this.settings?.vpn_routes ?? false)
      }
      this.switchRow('高级模式', '', 'dev', this.settings?.dev ?? false)
      if (this.settings?.dev) {
        ListItem() {
          Row() {
            Text('自定义 DNS')
              .fontColor($r('sys.color.font_primary'))
              .fontSize(16)
            TextInput({ text: this.settings?.dns ?? '', placeholder: '223.5.5.5' })
              .padding(0)
              .textAlign(TextAlign.End)
              .backgroundColor(Color.Transparent)
              .height('100%')
              .layoutWeight(1)
              .onChange((value: string) => this.setText('dns', value.length > 0 ? value : '223.5.5.5'))
          }
          .height(49)
          .borderRadius(18)
          .alignItems(VerticalAlign.Center)
          .justifyContent(FlexAlign.SpaceBetween)
          .width('100%')
          .backgroundColor($r('sys.color.comp_background_primary'))
          .shadow({
            radius: 7,
            color: '#1F000000'
          })
          .padding({ left: 12, right: 12 })
        }
        .margin({ bottom: 10 })
        this.switchRow('添加全局路由', '', 'force_global', this.settings?.force_global ?? true)
      }
    }
  }

  @Builder
  private logsContent() {
    ListItemGroup({ header: remoteSettingHeader('日志') }) {
      this.switchRow('记录内核日志', '', 'core_log', this.settings?.core_log ?? false)
      this.switchRow('记录调试日志', '', 'debug_log', this.settings?.debug_log ?? false)
    }
  }

  @Builder
  private permissionsContent() {
    ListItemGroup({ header: remoteSettingHeader('权限') }) {
      this.permissionRow('分布式权限', this.settings?.distributePerm ?? false, 'distributed')
    }
  }

  build() {
    HdsNavigation() {
      List() {
        ListItem()
          .height(64)
        if (this.category === 'runtime') {
          this.runtimeContent()
        } else if (this.category === 'advanced') {
          this.advancedContent()
        } else if (this.category === 'logs') {
          this.logsContent()
        } else if (this.category === 'permissions') {
          this.permissionsContent()
        }
        ListItem()
          .height(120)
      }
      .width('100%')
      .height('100%')
      .padding({ left: 15, right: 15 })
      .scrollBar(BarState.Auto)
    }
    .titleBar({
      style: remoteSettingTitleStyle(),
      content: {
        title: {
          mainTitle: this.title,
          subTitle: this.remoteDeviceName
        },
        menu: {
          value: [HdsMenuButton('刷新', $r('sys.symbol.arrow_2_circlepath'), () => this.refresh())]
        }
      }
    })
    .mode(NavigationMode.Stack)
    .titleMode(HdsNavigationTitleMode.MINI)
    .hideBackButton(false)
    .hideTitleBar(false)
    .backgroundColor($r('sys.color.background_secondary'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
