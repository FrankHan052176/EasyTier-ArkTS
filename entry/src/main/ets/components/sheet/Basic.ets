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
import { peerProtocols, protocolsWithoutTXT } from '../../util/Conversion'
import { EventHelper } from '../../util/EventHelper'
import { Rename_Content } from './Rename'
import { hdsMaterial, HdsNavigation, HdsNavigationMenuItemOptions, HdsNavigationTitleMode,
  TitleBarStyleOptions } from '@kit.UIDesignKit'
import { deviceInfo } from '@kit.BasicServicesKit'
import { LengthMetrics } from '@kit.ArkUI'

@Builder
export function SheetContentBuilder(type: string) {
  SheetContent({ type: type })
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
    EventHelper.emitterPublish('edit_close_sheet')
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
    if (this.type.startsWith('add_')) {
      clearEditValue(this.addFieldType)
    }
    this.closeSheet()
  }

  private titleText(): string {
    if (this.type.startsWith('add_')) {
      return `添加 ${this.getFieldDisplayName(this.addFieldName)}`
    }
    if (this.type.startsWith('edit_')) {
      return `编辑 ${this.getFieldDisplayName(this.editFieldName)}`
    }
    if (this.type === 'rename') {
      return '重命名'
    }
    return this.type
  }

  private titleMenus(): HdsNavigationMenuItemOptions[] {
    if (this.type.startsWith('add_')) {
      return [
        HdsMenuButton('取消', $r('sys.symbol.xmark'), () => this.secondaryAction()),
        HdsMenuButton('完成', $r('sys.symbol.checkmark'), () => this.primaryAction())
      ]
    }
    if (this.type.startsWith('edit_')) {
      return [HdsMenuButton('完成', $r('sys.symbol.checkmark'), () => this.primaryAction())]
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

  navTitleStyle(): TitleBarStyleOptions {
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
        systemMaterialEffect: {
          materialType: hdsMaterial.MaterialType.ADAPTIVE,
          materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
        }
      }
    }else {
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
              mainTitleColor: $r("sys.color.font_primary"),
              subTitleColor: $r("sys.color.font_secondary")
            },
            menuStyle: {
              iconColor: $r("sys.color.font_primary"),
              backgroundColor: $r("sys.color.background_primary")
            },
            backIconStyle: {
              iconColor: $r("sys.color.font_primary"),
              backgroundColor: $r("sys.color.background_primary")
            }
          }
        }
      }
    }
  }

  build() {
    HdsNavigation() {
      Column() {
        Column()
          .height(64)
        if (this.type.startsWith("add_")) {
          if (this.addFieldType === "cidr" || this.addFieldType === "route") {
            CidrEditor()
          } else if (this.addFieldType === "peer") {
            UrlEditor({ protocolArr: peerProtocols })
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
            UrlEditor({ protocolArr: peerProtocols })
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
        } else {
          Text(this.type)
        }
      }
    }
    .backgroundColor($r("sys.color.background_secondary"))
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
