import { common, contextConstant, StartOptions, Want } from '@kit.AbilityKit'
import { JSON } from '@kit.ArkTS'
import { BusinessError } from '@kit.BasicServicesKit'
import { statusBarManager } from '@kit.DeskTopExtensionKit'
import { image } from '@kit.ImageKit'
import { Logger } from '../../shared/logging/Logger'
import {
  APP_BUNDLE_NAME,
  ENTRY_ABILITY_NAME,
  ENTRY_MODULE_NAME,
  STATUS_BAR_BACKGROUND_ABILITY_NAME,
  STATUS_BAR_VIEW_ABILITY_NAME,
  supportsStatusBarTray
} from '../runtime/AbilityRuntimePolicy'
import { STATUS_BAR_PANEL_SOCKET_NAME } from './StatusBarPanelTypes'
import { StatusBarPanelServer } from './StatusBarPanelServer'

export class StatusBarIntegrationService {
  private readonly context: common.UIAbilityContext
  private readonly logTarget: Object | string
  private readonly panelServer: StatusBarPanelServer
  private registered: boolean = false
  private backgroundStarted: boolean = false

  constructor(context: common.UIAbilityContext, logTarget: Object | string, openMainWindow?: () => void) {
    this.context = context
    this.logTarget = logTarget
    this.panelServer = new StatusBarPanelServer(context, logTarget, openMainWindow)
  }

  async start(): Promise<void> {
    this.panelServer.start(`${this.context.filesDir}/${STATUS_BAR_PANEL_SOCKET_NAME}`)
    if (!supportsStatusBarTray()) {
      return
    }
    await this.registerStatusBarItem()
    this.startBackgroundAbility()
  }

  private async registerStatusBarItem(): Promise<void> {
    if (this.registered) {
      return
    }
    try {
      const icon = await this.createStatusBarIcon()
      const item: statusBarManager.StatusBarItem = {
        icons: icon,
        quickOperation: {
          abilityName: STATUS_BAR_VIEW_ABILITY_NAME,
          moduleName: ENTRY_MODULE_NAME,
          title: 'EasyTier',
          height: 260
        },
        statusBarGroupMenu: [[{
          title: '打开 EasyTier',
          menuAction: {
            abilityName: ENTRY_ABILITY_NAME,
            moduleName: ENTRY_MODULE_NAME
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

  private startBackgroundAbility(): void {
    if (this.backgroundStarted || !this.registered) {
      return
    }
    const want: Want = {
      bundleName: APP_BUNDLE_NAME,
      abilityName: STATUS_BAR_BACKGROUND_ABILITY_NAME
    }
    const options: StartOptions = {
      processMode: contextConstant.ProcessMode.NEW_PROCESS_ATTACH_TO_STATUS_BAR_ITEM,
      startupVisibility: contextConstant.StartupVisibility.STARTUP_HIDE
    }
    try {
      this.context.startAbility(want, options, (err: BusinessError) => {
        if (err.code) {
          Logger.error(`status bar background start failed: ${err.code}, ${err.message}`, this.logTarget)
          return
        }
        this.backgroundStarted = true
        Logger.info('status bar background started', this.logTarget)
      })
    } catch (error) {
      Logger.error(`status bar background start error: ${JSON.stringify(error)}`, this.logTarget)
    }
  }

  close(): void {
    this.panelServer.close()
    if (!this.registered) {
      return
    }
    try {
      statusBarManager.removeFromStatusBar(this.context)
      Logger.info('status bar item removed', this.logTarget)
    } catch (error) {
      Logger.debug(`status bar item remove ignored: ${JSON.stringify(error)}`, this.logTarget)
    }
    this.registered = false
    this.backgroundStarted = false
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
