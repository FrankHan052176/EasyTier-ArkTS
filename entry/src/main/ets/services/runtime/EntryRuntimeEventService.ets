import { JSON } from '@kit.ArkTS'
import { emitter } from '@kit.BasicServicesKit'
import { ConfigJson } from '../../config/schema/SchemaConfig'
import { Logger } from '../../shared/logging/Logger'
import { EventHelper } from '../../util/EventHelper'
import {
  CHANGE_IPV4_EVENT,
  ENTRY_SYNC_CONTINUATION_SOCKET_EVENT,
  SETUP_TUN_EVENT,
  START_BACKGROUND_EVENT,
  STOP_BACKGROUND_EVENT
} from '../../types/events/RuntimeEventTypes'
import { EntryVpnSetupRequest } from '../tun/EntryVpnConnectionService'

export interface EntryRuntimeEventServiceOptions {
  logTarget: Object | string
  syncContinuationSocket: () => void
  prepareVpn: (shouldProtect: boolean, callback: () => void) => void
  shouldProtectProcessNet: (config?: ConfigJson) => boolean
  getKernelSocketPath: () => string
  connectToKernelSocket: (socketPath: string) => void
  startContinuousTask: (cfg: string, uuid: string | undefined, name: string | undefined) => void
  stopContinuousTask: () => void
  closeKernelSocket: () => void
  buildTunSetupRequest: (data: emitter.EventData) => EntryVpnSetupRequest
  setupTun: (request: EntryVpnSetupRequest) => void
}

export class EntryRuntimeEventService {
  private readonly logTarget: Object | string
  private readonly syncContinuationSocket: () => void
  private readonly prepareVpn: (shouldProtect: boolean, callback: () => void) => void
  private readonly shouldProtectProcessNet: (config?: ConfigJson) => boolean
  private readonly getKernelSocketPath: () => string
  private readonly connectToKernelSocket: (socketPath: string) => void
  private readonly startContinuousTask: (cfg: string, uuid: string | undefined, name: string | undefined) => void
  private readonly stopContinuousTask: () => void
  private readonly closeKernelSocket: () => void
  private readonly buildTunSetupRequest: (data: emitter.EventData) => EntryVpnSetupRequest
  private readonly setupTun: (request: EntryVpnSetupRequest) => void

  private readonly entrySyncContinuationSocketCallback = () => {
    this.syncContinuationSocket()
  }
  private readonly startBgCallback = (data: emitter.EventData) => {
    let shouldProtect = false
    const cfg = data.data?.cfg as string | undefined
    try {
      if (cfg) {
        const config: ESObject = JSON.parse(cfg)
        shouldProtect = this.shouldProtectProcessNet(config)
      }
    } catch (error) {
    }
    this.prepareVpn(shouldProtect, () => {
      Logger.info("start_bg_task", this.logTarget)
      this.connectToKernelSocket(this.getKernelSocketPath())
      this.startContinuousTask(cfg ?? '', data.data?.uuid, data.data?.name)
    })
  }
  private readonly stopBgCallback = () => {
    Logger.info("stop_bg_task", this.logTarget)
    this.stopContinuousTask()
    this.closeKernelSocket()
  }
  private readonly setupTunCallback = (data: emitter.EventData) => {
    Logger.info("setup_tun", this.logTarget)
    this.setupTun(this.buildTunSetupRequest(data))
  }
  private readonly changeIpv4Callback = (data: emitter.EventData) => {
    Logger.info("change_ipv4", this.logTarget)
    this.setupTun(this.buildTunSetupRequest(data))
  }

  constructor(options: EntryRuntimeEventServiceOptions) {
    this.logTarget = options.logTarget
    this.syncContinuationSocket = options.syncContinuationSocket
    this.prepareVpn = options.prepareVpn
    this.shouldProtectProcessNet = options.shouldProtectProcessNet
    this.getKernelSocketPath = options.getKernelSocketPath
    this.connectToKernelSocket = options.connectToKernelSocket
    this.startContinuousTask = options.startContinuousTask
    this.stopContinuousTask = options.stopContinuousTask
    this.closeKernelSocket = options.closeKernelSocket
    this.buildTunSetupRequest = options.buildTunSetupRequest
    this.setupTun = options.setupTun
  }

  start(): void {
    EventHelper.emitterListener(ENTRY_SYNC_CONTINUATION_SOCKET_EVENT, this.entrySyncContinuationSocketCallback)
    EventHelper.emitterListener(START_BACKGROUND_EVENT, this.startBgCallback)
    EventHelper.emitterListener(STOP_BACKGROUND_EVENT, this.stopBgCallback)
    EventHelper.emitterListener(SETUP_TUN_EVENT, this.setupTunCallback)
    EventHelper.emitterListener(CHANGE_IPV4_EVENT, this.changeIpv4Callback)
  }

  stop(): void {
    EventHelper.emitterOff(ENTRY_SYNC_CONTINUATION_SOCKET_EVENT, this.entrySyncContinuationSocketCallback)
    EventHelper.emitterOff(START_BACKGROUND_EVENT, this.startBgCallback)
    EventHelper.emitterOff(STOP_BACKGROUND_EVENT, this.stopBgCallback)
    EventHelper.emitterOff(SETUP_TUN_EVENT, this.setupTunCallback)
    EventHelper.emitterOff(CHANGE_IPV4_EVENT, this.changeIpv4Callback)
  }
}
