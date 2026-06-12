import { common } from '@kit.AbilityKit'
import { JSON } from '@kit.ArkTS'
import { statusBarManager } from '@kit.DeskTopExtensionKit'
import { image } from '@kit.ImageKit'
import { Logger } from '../../shared/logging/Logger'
import { STATUS_BAR_PANEL_SOCKET_NAME } from './StatusBarPanelTypes'
import { StatusBarPanelServer } from './StatusBarPanelServer'

export class StatusBarIntegrationService {
  private readonly context: common.UIAbilityContext
  private readonly logTarget: Object | string
  private readonly panelServer: StatusBarPanelServer
  private registered: boolean = false

  constructor(context: common.UIAbilityContext, logTarget: Object | string, openMainWindow?: () => void) {
    this.context = context
    this.logTarget = logTarget
    this.panelServer = new StatusBarPanelServer(context, logTarget, openMainWindow)
  }

  async start(): Promise<void> {
    this.panelServer.start(`${this.context.filesDir}/${STATUS_BAR_PANEL_SOCKET_NAME}`)
    if (this.registered || !canIUse('SystemCapability.PCService.StatusBarManager')) {
      return
    }
    try {
      const icon = await this.createStatusBarIcon()
      const item: statusBarManager.StatusBarItem = {
        icons: icon,
        quickOperation: {
          abilityName: 'StatusBarViewAbility',
          moduleName: 'entry',
          title: 'EasyTier',
          height: 260
        },
        statusBarGroupMenu: [[{
          title: '打开 EasyTier',
          menuAction: {
            abilityName: 'EntryAbility',
            moduleName: 'entry'
          }
        }]],
        hoverTips: 'EasyTier'
      }
      statusBarManager.addToStatusBar(this.context, item)
      this.registered = true
      Logger.info('status bar item registered', this.logTarget)
    } catch (error) {
      Logger.error(`status bar item register failed: ${JSON.stringify(error)}`, this.logTarget)
    }
  }

  close(): void {
    this.panelServer.close()
  }

  broadcastState(): void {
    this.panelServer.broadcastState()
  }

  private async createStatusBarIcon(): Promise<statusBarManager.StatusBarIcon> {
    const data = this.context.resourceManager.getMediaContentSync($r('app.media.easytier').id)
    const source = image.createImageSource(data.buffer.slice(0, data.buffer.byteLength))
    const white = await source.createPixelMap({ desiredSize: { width: 24, height: 24 } })
    const source2 = image.createImageSource(data.buffer.slice(0, data.buffer.byteLength))
    const black = await source2.createPixelMap({ desiredSize: { width: 24, height: 24 } })
    return { white, black }
  }
}
