import { emitter } from '@kit.BasicServicesKit'
import { Logger } from '../../shared/logging/Logger'
import { EventHelper } from '../../util/EventHelper'
import {
  CHANGE_IPV4_EVENT,
  ENTRY_SYNC_CONTINUATION_SOCKET_EVENT,
  SETUP_TUN_EVENT
} from '../../types/events/RuntimeEventTypes'
import { EntryVpnSetupRequest } from '../tun/EntryVpnConnectionService'

export interface EntryRuntimeEventServiceOptions {
  logTarget: Object | string
  syncContinuationSocket: () => void
  buildTunSetupRequest: (data: emitter.EventData) => EntryVpnSetupRequest
  setupTun: (request: EntryVpnSetupRequest) => void
}

export class EntryRuntimeEventService {
  private readonly logTarget: Object | string
  private readonly syncContinuationSocket: () => void
  private readonly buildTunSetupRequest: (data: emitter.EventData) => EntryVpnSetupRequest
  private readonly setupTun: (request: EntryVpnSetupRequest) => void

  private readonly entrySyncContinuationSocketCallback = () => {
    this.syncContinuationSocket()
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
    this.buildTunSetupRequest = options.buildTunSetupRequest
    this.setupTun = options.setupTun
  }

  start(): void {
    EventHelper.emitterListener(ENTRY_SYNC_CONTINUATION_SOCKET_EVENT, this.entrySyncContinuationSocketCallback)
    EventHelper.emitterListener(SETUP_TUN_EVENT, this.setupTunCallback)
    EventHelper.emitterListener(CHANGE_IPV4_EVENT, this.changeIpv4Callback)
  }

  stop(): void {
    EventHelper.emitterOff(ENTRY_SYNC_CONTINUATION_SOCKET_EVENT, this.entrySyncContinuationSocketCallback)
    EventHelper.emitterOff(SETUP_TUN_EVENT, this.setupTunCallback)
    EventHelper.emitterOff(CHANGE_IPV4_EVENT, this.changeIpv4Callback)
  }
}
