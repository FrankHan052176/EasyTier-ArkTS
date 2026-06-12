import { HdsNavigation, HdsNavigationMenuItemOptions, HdsNavigationTitleMode, HdsNavDestination,
  HdsNavDestinationTitleMode, hdsMaterial, TitleBarStyleOptions } from '@kit.UIDesignKit'
import { deviceInfo } from '@kit.BasicServicesKit'
import { LengthMetrics } from '@kit.ArkUI'
import { HdsMenuButton } from '../../pages/Components'
import { EventHelper } from '../../util/EventHelper'
import { AppManager } from '../../AppManager'
import { config_name, NewConfig_Content, setConfigName } from './NewConfig'
import { SettingAdvanced_Content, SettingAbout_Content, SettingCloudSync_Content, SettingLogs_Content,
  SettingPermissions_Content, Setting_Sheet } from './Settings'
import { UI_Content } from './UIModifier'
import { BlackList_Content } from './BlackList'

@Builder
export function HomeSheetContentBuilder(type: string) {
  HomeSheetContent({ type })
}

@ComponentV2
struct HomeSheetContent {
  @Param @Require type: string
  private settingPathStack: NavPathStack = new NavPathStack()

  private closeSheet(): void {
    if (this.type === 'setting') {
      this.settingPathStack.clear(false)
    }
    EventHelper.emitterPublish('home_close_sheet')
  }

  private primaryAction(): void {
    if (this.type === 'new') {
      if (config_name !== undefined && config_name.length > 0) {
        AppManager.data.newConfig(config_name)
        setConfigName(undefined)
        this.closeSheet()
      } else {
        EventHelper.emitterPublish('new_config_popup')
      }
      return
    }
    this.closeSheet()
  }

  private secondaryAction(): void {
    if (this.type === 'new') {
      setConfigName(undefined)
    }
    this.closeSheet()
  }

  private titleText(): string {
    if (this.type === 'new') {
      return '新建实例'
    }
    if (this.type === 'setting') {
      return '设置'
    }
    if (this.type === 'logs') {
      return '日志与调试'
    }
    if (this.type === 'ui') {
      return 'UI 设置'
    }
    if (this.type === 'black_list') {
      return AppManager.uiState.white_list ? 'App 白名单' : 'App 黑名单'
    }
    return this.type
  }

  private titleMenus(): HdsNavigationMenuItemOptions[] {
    if (this.type === 'new') {
      return [
        HdsMenuButton('取消', $r('sys.symbol.xmark'), () => this.secondaryAction()),
        HdsMenuButton('完成', $r('sys.symbol.checkmark'), () => this.primaryAction())
      ]
    }
    if (this.type === 'black_list') {
      return [
        HdsMenuButton('切换', $r('sys.symbol.arrow_2_circlepath'), () => {
          AppManager.uiState.white_list = !AppManager.uiState.white_list
        }),
        HdsMenuButton('关闭', $r('sys.symbol.xmark'), () => this.closeSheet())
      ]
    }
    return [HdsMenuButton('关闭', $r('sys.symbol.xmark'), () => this.closeSheet())]
  }

  private navTitleStyle(): TitleBarStyleOptions {
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

  private openSettingPage(page: string): void {
    this.settingPathStack.pushPath(new NavPathInfo(page, null))
  }

  private settingDestinationTitle(page: string): string {
    if (page === 'ui') {
      return 'UI 设置'
    }
    if (page === 'black_list') {
      return AppManager.uiState.white_list ? 'App 白名单' : 'App 黑名单'
    }
    if (page === 'cloud_sync') {
      return '云空间同步'
    }
    if (page === 'logs') {
      return '日志与调试'
    }
    if (page === 'permissions') {
      return '权限'
    }
    if (page === 'advanced') {
      return '高级设置'
    }
    if (page === 'about') {
      return '关于与帮助'
    }
    return page
  }

  private settingDestinationMenus(page: string): HdsNavigationMenuItemOptions[] {
    if (page === 'black_list') {
      return [
        HdsMenuButton('切换', $r('sys.symbol.arrow_2_circlepath'), () => {
          AppManager.uiState.white_list = !AppManager.uiState.white_list
        }),
        HdsMenuButton('关闭', $r('sys.symbol.xmark'), () => this.closeSheet())
      ]
    }
    return [HdsMenuButton('关闭', $r('sys.symbol.xmark'), () => this.closeSheet())]
  }

  @Builder
  settingDestination(page: string, pageInfos: Object) {
    HdsNavDestination() {
      Column() {
        if (page === 'ui') {
          UI_Content()
        } else if (page === 'black_list') {
          BlackList_Content()
        } else if (page === 'cloud_sync') {
          SettingCloudSync_Content()
        } else if (page === 'logs') {
          SettingLogs_Content()
        } else if (page === 'permissions') {
          SettingPermissions_Content()
        } else if (page === 'advanced') {
          SettingAdvanced_Content()
        } else if (page === 'about') {
          SettingAbout_Content()
        } else {
          Text(page)
        }
      }
    }
    .titleBar({
      style: this.navTitleStyle(),
      content: {
        title: {
          mainTitle: this.settingDestinationTitle(page)
        },
        menu: {
          value: this.settingDestinationMenus(page)
        }
      }
    })
    .titleMode(HdsNavDestinationTitleMode.MODAL)
    .hideBackButton(false)
    .hideTitleBar(false)
    .backgroundColor($r("sys.color.background_secondary"))
  }

  build() {
    if (this.type === 'setting') {
      HdsNavigation(this.settingPathStack) {
        Setting_Sheet((page: string) => this.openSettingPage(page))
      }
      .backgroundColor($r('sys.color.background_secondary'))
      .titleBar({
        style: this.navTitleStyle(),
        content: {
          title: {
            mainTitle: this.titleText()
          },
          menu: {
            value: this.titleMenus()
          }
        },
      })
      .navDestination(this.settingDestination)
      .mode(NavigationMode.Stack)
      .titleMode(HdsNavigationTitleMode.MODAL)
      .hideBackButton(true)
      .hideTitleBar(false)
    } else {
      HdsNavigation() {
        Column() {
          Column().height(64)
          if (this.type === 'new') {
            NewConfig_Content()
          } else if (this.type === 'logs') {
            SettingLogs_Content()
          } else if (this.type === 'ui') {
            UI_Content()
          } else if (this.type === 'black_list') {
            BlackList_Content()
          } else {
            Text(this.type)
          }
        }
      }
      .backgroundColor($r('sys.color.background_secondary'))
      .titleBar({
        style: this.navTitleStyle(),
        content: {
          title: {
            mainTitle: this.titleText()
          },
          menu: {
            value: this.titleMenus()
          }
        },
      })
      .titleMode(HdsNavigationTitleMode.MODAL)
      .hideBackButton(true)
      .hideTitleBar(false)
    }
  }
}
