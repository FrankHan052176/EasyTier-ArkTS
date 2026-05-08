import { CidrEditor } from '../../class/config/Cidr'
import { IPEditor } from '../../class/config/IP'
import { NetworkNameEditor } from '../../class/config/NetworkName'
import { PortForwardEditor } from '../../class/config/PortForward'
import { UrlEditor } from '../../class/config/Url'
import { AppManager } from '../../AppManager'
import { addValue, clearEditValue, commitEditValue, confirmCheck } from '../../class/config/Basic'
import { syncTopLevelField } from '../../ConfigSyncUtil'
import { ConfigJson } from '../../config/schema/SchemaConfig'
import { HdsMenuButton } from '../../pages/Components'
import { protocolsWithoutTXT } from '../../util/Conversion'
import { EventHelper } from '../../util/EventHelper'
import { AddTitle, EditTitle } from './AddAndEditTitle'
import { BlackList_Content, BlackList_Title } from './BlackList'
import { config_name, NewConfig_Content, NewConfig_Title, setConfigName } from './NewConfig'
import { Rename_Content, Rename_Title } from './Rename'
import { Setting_Sheet, Setting_Title } from './Settings'
import { UI_Content, UI_Title } from './UIModifier'
import { hdsMaterial, HdsNavigation, HdsNavigationMenuItemOptions, HdsNavigationTitleMode } from '@kit.UIDesignKit'
import { deviceInfo } from '@kit.BasicServicesKit'
import { LengthMetrics } from '@kit.ArkUI'

@Builder
export function SheetContentBuilder(type: string) {
  SheetContent({ type: type })
}

@Builder
export function SheetTitleBuilder(type: string) {
  Row() {
    SheetTitle({ type: type })
      .width('100%')
      .height('100%')
  }
  .width('100%')
  .height('100%')
}

@ComponentV2
export struct SheetContent {
  @Param @Require type: string

  private getFieldDisplayName(fieldName: string): string {
    try {
      return AppManager.content.context!.resourceManager.getStringSync($r('app.string.' + fieldName).id)
    } catch (_) {
      return fieldName
    }
  }

  private closeSheet(): void {
    if (this.type === 'new' || this.type === 'setting' || this.type === 'ui' || this.type === 'black_list') {
      EventHelper.emitterPublish('home_close_sheet')
    } else {
      EventHelper.emitterPublish('edit_close_sheet')
    }
  }

  private finishEdit(closeOnly: boolean = false): void {
    if (!confirmCheck(this.editFieldType)) {
      clearEditValue(this.editFieldType)
      this.closeSheet()
      return
    }
    const config: ConfigJson | undefined = AppManager.easytier.getEditingConfig()
    const configId: string | undefined = config?.instance_id
    if (!closeOnly && config && configId) {
      commitEditValue(config, this.editFieldName, this.editFieldType)
      syncTopLevelField(configId, this.editFieldName, config)
    }
    clearEditValue(this.editFieldType)
    this.closeSheet()
    EventHelper.emitterPublish('edit_refresh_' + this.editFieldName)
    AppManager.data.getDataSource(this.editFieldType).update()
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

    if (this.type.startsWith('add_')) {
      if (confirmCheck(this.addFieldType)) {
        addValue(this.addFieldName, this.addFieldType)
        clearEditValue(this.addFieldType)
        EventHelper.emitterPublish('edit_refresh_' + this.addFieldName)
        this.closeSheet()
      }
      return
    }

    if (this.type.startsWith('edit_')) {
      this.finishEdit(false)
      return
    }

    this.closeSheet()
  }

  private secondaryAction(): void {
    if (this.type === 'new') {
      setConfigName(undefined)
    } else if (this.type.startsWith('add_')) {
      clearEditValue(this.addFieldType)
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
    if (this.type.startsWith('add_')) {
      return `添加 ${this.getFieldDisplayName(this.addFieldName)}`
    }
    if (this.type.startsWith('edit_')) {
      return `编辑 ${this.getFieldDisplayName(this.editFieldName)}`
    }
    if (this.type === 'rename') {
      return '重命名'
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
    if (this.type === 'new' || this.type.startsWith('add_')) {
      return [
        HdsMenuButton('取消', $r('sys.symbol.xmark'), () => this.secondaryAction()),
        HdsMenuButton('完成', $r('sys.symbol.checkmark'), () => this.primaryAction())
      ]
    }
    if (this.type.startsWith('edit_')) {
      return [HdsMenuButton('完成', $r('sys.symbol.checkmark'), () => this.primaryAction())]
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

  @Computed
  get addFieldType() {
    let result = this.type.substring(4).substring(0, this.type.substring(4).indexOf('|'))
    return result
  }

  @Computed
  get addFieldName() {
    let result = this.type.substring(4).substring(this.type.substring(4).indexOf('|') + 1)
    return result
  }

  @Computed
  get editFieldType() {
    return this.type.substring(5).substring(0, this.type.substring(5).indexOf('|'))
  }

  @Computed
  get editFieldName() {
    return this.type.substring(5).substring(this.type.substring(5).indexOf('|') + 1)
  }

  build() {
    HdsNavigation() {
      if (this.type === "setting") {
        Setting_Sheet()
      }else {
        Column() {
          Column()
            .height(64)
          if (this.type === "new") {
            NewConfig_Content()
          } else if (this.type.startsWith("add_")) {
            if (this.addFieldType === "cidr" || this.addFieldType === "route") {
              CidrEditor()
            } else if (this.addFieldType === "peer") {
              UrlEditor()
            } else if (this.addFieldType === "listener" || this.addFieldType === "mapped_listener") {
              UrlEditor({ protocolArr: protocolsWithoutTXT })
            } else if (this.addFieldType === "ip") {
              IPEditor()
            } else if (this.addFieldType === "network_name") {
              NetworkNameEditor()
            } else if (this.addFieldType === "port_forward") {
              PortForwardEditor()
            }
          } else if (this.type.startsWith("edit_")) {
            if (this.editFieldType === "cidr" || this.editFieldType === "route") {
              CidrEditor()
            } else if (this.editFieldType === "peer") {
              UrlEditor()
            } else if (this.editFieldType === "listener" || this.editFieldType === "mapped_listener") {
              UrlEditor({ protocolArr: protocolsWithoutTXT })
            } else if (this.editFieldType === "ip") {
              IPEditor()
            } else if (this.editFieldType === "network_name") {
              NetworkNameEditor()
            } else if (this.editFieldType === "port_forward") {
              PortForwardEditor()
            }
          } else if (this.type === "rename") {
            Rename_Content()
          } else if (this.type === "ui") {
            UI_Content()
          } else if (this.type === "black_list") {
            BlackList_Content()
          } else {
            Text(this.type)
          }
        }
      }
    }
    .backgroundColor($r("sys.color.background_secondary"))
    .titleBar({
      style: {
        scrollEffectOpts: {
          enableScrollEffect: true,
          scrollEffectType: deviceInfo.sdkApiVersion >= 23 ? 3 : 2,
          blurEffectiveStartOffset: LengthMetrics.vp(0),
          blurEffectiveEndOffset: LengthMetrics.vp(20),
        },
        originalStyle: {
          contentStyle: {
            titleStyle: {
              mainTitleColor: $r("sys.color.font_primary"),
              subTitleColor: $r("sys.color.font_secondary")
            },
            menuStyle: {
              iconColor: $r("sys.color.font_primary")
            },
            backIconStyle: {
              iconColor: $r("sys.color.font_primary")
            }
          }
        },
        systemMaterialEffect: deviceInfo.sdkApiVersion >= 23 ? {
          materialType: hdsMaterial.MaterialType.ADAPTIVE,
          materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
        }: undefined
      },
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

@ComponentV2
export struct SheetTitle {
  @Param @Require type: string

  @Computed
  get addFieldType() {
    return this.type.substring(4).substring(0, this.type.substring(4).indexOf('|'))
  }

  @Computed
  get addFieldName() {
    return this.type.substring(4).substring(this.type.substring(4).indexOf('|') + 1)
  }

  @Computed
  get editFieldType() {
    return this.type.substring(5).substring(0, this.type.substring(5).indexOf('|'))
  }

  @Computed
  get editFieldName() {
    return this.type.substring(5).substring(this.type.substring(5).indexOf('|') + 1)
  }

  build() {
    if (this.type === "new") {
      NewConfig_Title()
    } else if (this.type === "setting") {
      Setting_Title()
    } else if (this.type.startsWith("add_")) {
      AddTitle({ fieldType: this.addFieldType, fieldName: this.addFieldName })
    } else if (this.type.startsWith("edit_")) {
      EditTitle({ fieldType: this.editFieldType, fieldName: this.editFieldName })
    } else if (this.type === "rename") {
      Rename_Title()
    } else if (this.type === "ui") {
      UI_Title()
    } else if (this.type === "black_list") {
      BlackList_Title()
    } else {
      Text(this.type)
    }
  }
}
