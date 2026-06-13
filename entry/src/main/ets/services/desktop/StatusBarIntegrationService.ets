import { common, contextConstant, StartOptions, Want } from '@kit.AbilityKit'
import { JSON } from '@kit.ArkTS'
import { BusinessError, emitter } from '@kit.BasicServicesKit'
import { statusBarManager } from '@kit.StatusBarExtensionKit'
import { image } from '@kit.ImageKit'
import { Logger } from '../../shared/logging/Logger'
import {
  APP_BUNDLE_NAME,
  ENTRY_ABILITY_NAME,
  ENTRY_MODULE_NAME,
  STATUS_BAR_BACKGROUND_ABILITY_NAME,
  setStatusBarTraySupported
} from '../runtime/AbilityRuntimePolicy'

const STATUS_BAR_MENU_CODE_EXIT = 'easytier_status_bar_exit'
const STATUS_BAR_MENU_CODE_OPEN = 'easytier_status_bar_open'

export class StatusBarIntegrationService {
  private readonly context: common.UIAbilityContext
  private readonly logTarget: Object | string
  private readonly openMainWindow: (() => void) | undefined
  private registered: boolean = false
  private backgroundStarted: boolean = false
  private readonly terminateApp: (() => void) | undefined
  private readonly iconClickCallback: Callback<emitter.EventData> = (eventData: emitter.EventData) => {
    const clickType = eventData.data?.['iconClickType'] as string | undefined
    if (clickType === 'leftClick') {
      this.openMainWindow?.()
    }
  }
  private readonly rightMenuClickCallback: Callback<emitter.EventData> = (eventData: emitter.EventData) => {
    const menuCode = eventData.data?.['menuCode'] as string | undefined
    if (menuCode === STATUS_BAR_MENU_CODE_OPEN) {
      this.openMainWindow?.()
    } else if (menuCode === STATUS_BAR_MENU_CODE_EXIT) {
      this.terminateApp?.()
    }
  }

  constructor(context: common.UIAbilityContext, logTarget: Object | string, openMainWindow?: () => void, terminateApp?: () => void) {
    this.context = context
    this.logTarget = logTarget
    this.openMainWindow = openMainWindow
    this.terminateApp = terminateApp
  }

  async start(): Promise<void> {
    setStatusBarTraySupported(false)
    const registered = await this.registerStatusBarItem()
    setStatusBarTraySupported(registered)
    if (!registered) {
      return
    }
    setTimeout(() => {
      this.startBackgroundAbility()
    }, 300)
  }

  private async registerStatusBarItem(): Promise<boolean> {
    if (this.registered) {
      return true
    }
    try {
      const icon = await this.createStatusBarIcon()
      const item: statusBarManager.StatusBarItem = {
        icons: icon,
        quickOperation: {
          abilityName: '',
          moduleName: ENTRY_MODULE_NAME,
          title: 'EasyTier',
          height: 1
        },
        statusBarGroupMenu: [[
          {
            title: '打开 EasyTier',
            menuAction: {
              abilityName: ENTRY_ABILITY_NAME,
              moduleName: ENTRY_MODULE_NAME,
              menuCode: STATUS_BAR_MENU_CODE_OPEN,
              notifyOnly: true
            }
          }
        ]],
        hoverTips: 'EasyTier'
      }
      statusBarManager.addToStatusBar(this.context, item)
      statusBarManager.on('statusBarIconClick', this.iconClickCallback)
      statusBarManager.on('rightMenuClick', this.rightMenuClickCallback)
      this.registered = true
      Logger.info('status bar item registered', this.logTarget)
      return true
    } catch (error) {
      Logger.error(`status bar item register failed: ${JSON.stringify(error)}`, this.logTarget)
      return false
    }
  }

  private startBackgroundAbility(): void {
    if (this.backgroundStarted || !this.registered) {
      return
    }
    const want: Want = {
      bundleName: APP_BUNDLE_NAME,
      moduleName: ENTRY_MODULE_NAME,
      abilityName: STATUS_BAR_BACKGROUND_ABILITY_NAME
    }
    const options: StartOptions = {
      processMode: contextConstant.ProcessMode.NEW_PROCESS_ATTACH_TO_STATUS_BAR_ITEM,
      startupVisibility: contextConstant.StartupVisibility.STARTUP_HIDE
    }
    try {
      this.context.startAbility(want, options, (err: BusinessError) => {
        if (err.code) {
          Logger.debug(`status bar background attach ignored: ${err.code}, ${err.message}`, this.logTarget)
          return
        }
        this.backgroundStarted = true
        Logger.info('status bar background started', this.logTarget)
      })
    } catch (error) {
      Logger.debug(`status bar background attach error ignored: ${JSON.stringify(error)}`, this.logTarget)
    }
  }

  close(): void {
    if (!this.registered) {
      return
    }
    try {
      statusBarManager.off('statusBarIconClick', this.iconClickCallback)
      statusBarManager.off('rightMenuClick', this.rightMenuClickCallback)
      statusBarManager.removeFromStatusBar(this.context)
      Logger.info('status bar item removed', this.logTarget)
    } catch (error) {
      Logger.debug(`status bar item remove ignored: ${JSON.stringify(error)}`, this.logTarget)
    }
    this.registered = false
    this.backgroundStarted = false
    setStatusBarTraySupported(false)
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
