import { HdsNavigation, HdsNavigationMenuItemOptions, HdsNavigationTitleMode, hdsMaterial, TitleBarStyleOptions } from '@kit.UIDesignKit'
import { deviceInfo } from '@kit.BasicServicesKit'
import { LengthMetrics } from '@kit.ArkUI'
import { HdsMenuButton } from '../../pages/Components'
import { EventHelper } from '../../util/EventHelper'
import { AppManager } from '../../AppManager'
import { config_name, NewConfig_Content, setConfigName } from './NewConfig'
import { Setting_Sheet } from './Settings'
import { UI_Content } from './UIModifier'
import { BlackList_Content } from './BlackList'

@Builder
export function HomeSheetContentBuilder(type: string) {
  HomeSheetContent({ type })
}

@ComponentV2
struct HomeSheetContent {
  @Param @Require type: string

  private closeSheet(): void {
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
          this.closeSheet()
          setTimeout(() => {
            EventHelper.emitterPublish('home_open_sheet', {
              data: {
                type: 'black_list'
              }
            })
          }, 100)
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

  build() {
    HdsNavigation() {
      if (this.type === 'setting') {
        Setting_Sheet()
      } else {
        Column() {
          Column().height(64)
          if (this.type === 'new') {
            NewConfig_Content()
          } else if (this.type === 'ui') {
            UI_Content()
          } else if (this.type === 'black_list') {
            BlackList_Content()
          } else {
            Text(this.type)
          }
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
