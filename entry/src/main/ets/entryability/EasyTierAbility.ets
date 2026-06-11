import { VpnExtensionAbility } from '@kit.NetworkKit';
import { Logger } from '../shared/logging/Logger';
import Want from '@ohos.app.ability.Want';
import easytier from 'easytier-ohrs';
import { JSON } from '@kit.ArkTS';
import { ConfigJson } from '../config/schema/SchemaConfig';
import {
  KERNEL_SOCKET_NAME
} from '../infrastructure/bridge/kernel/KernelBridgeTypes'
import { VpnBridgeServer } from '../infrastructure/bridge/kernel/VpnBridgeServer'
import { startRuntimeStatsRecording, stopRuntimeStatsRecording } from '../services/runtime/RuntimeStatsService'
import { AppManager } from '../AppManager'
import { VpnExtensionKernelSocketService } from '../services/runtime/VpnExtensionKernelSocketService'
import { VpnExtensionTunService, VpnExtensionTunSettings } from '../services/tun/VpnExtensionTunService'

export default class EasyTierAbility extends VpnExtensionAbility {
  private bridgeServer: VpnBridgeServer = new VpnBridgeServer('EasyTierAbility')
  private kernelSocketService: VpnExtensionKernelSocketService = new VpnExtensionKernelSocketService({
    logTarget: 'EasyTierAbility',
    onTunRequest: (payload, trigger: string) => {
      this.tunService?.handleKernelTunRequest(payload, trigger)
    },
    broadcastRaw: (rawMessage: string) => {
      this.bridgeServer.broadcastRaw(rawMessage)
    }
  })
  private tunService: VpnExtensionTunService | undefined = undefined
  timer: number | undefined
  config: ConfigJson | undefined
  instance_id: string = ""
  socketFilesDir: string = ''
  core_log: boolean = false
  debug_log: boolean = false

  onCreate(want: Want): void {
    if (want.parameters == undefined) {
      easytier.initLogManager(this.context.filesDir, 'vpn')
      easytier.configureLogManager(false, false)
      Logger.debug("VpnExtAbi create without parameters", "EasyTierAbility")
      return;
    }
    const cfgParam = want.parameters["cfg"] as string | undefined
    this.socketFilesDir = want.parameters["socket_files_dir"] as string ?? this.context.filesDir;
    this.core_log = want.parameters["core_log"] as boolean ?? (want.parameters["show_log"] as boolean ?? false);
    this.debug_log = want.parameters["debug_log"] as boolean ?? false;
    easytier.initLogManager(this.socketFilesDir, 'vpn')
    easytier.configureLogManager(this.core_log, this.debug_log)
    Logger.debug("VpnExtAbi create", "EasyTierAbility")
    if (!cfgParam) {
      Logger.debug("VpnExtAbi create without cfg, likely permission probe", "EasyTierAbility")
      return
    }
    this.bridgeServer.start(this.socketFilesDir, want.parameters["socket"] as string);
    this.config = JSON.parse(cfgParam) as ConfigJson;
    this.instance_id = this.config.instance_id!!;
    const tunSettings: VpnExtensionTunSettings = {
      whiteList: want.parameters["white_list"] as boolean ?? false,
      blackList: want.parameters["black_list"] as string[] ?? [],
      dns: want.parameters["dns"] as string ?? "",
      dev: want.parameters["dev"] as boolean ?? false,
      forceGlobal: want.parameters["force_global"] as boolean ?? true
    }
    this.tunService = new VpnExtensionTunService({
      context: this.context,
      logTarget: 'EasyTierAbility',
      instanceId: this.instance_id,
      config: this.config,
      settings: tunSettings,
      publishContinuationState: (active: boolean) => {
        this.bridgeServer.publishContinuationState(active)
      },
      setTunFd: (instanceId: string, fd: number) => {
        easytier.setTunFd(instanceId, fd)
      }
    })
    if (!easytier.initConfigStore(this.socketFilesDir)) {
      Logger.error(`initConfigStore failed filesDir=${this.socketFilesDir}`, "EasyTierAbility")
      return
    }
    easytier.initPanicHook();

    if (this.core_log) {
      easytier.initTracingSubscriber();
    }
    this.tunService.prepareProtection().catch((err: Error) => {
      Logger.error(`protectProcessNet failed before kernel start: ${JSON.stringify(err)}`, "EasyTierAbility")
    }).finally(() => {
      this.startCollecting();
      this.startKernel();
    })
  }

  onDestroy(): void {
    Logger.debug("VpnExtAbi destroy", "EasyTierAbility")
    this.bridgeServer.publishContinuationState(false)
    if (this.timer) {
      clearInterval(this.timer);
    }
    this.stopKernel();
    this.kernelSocketService.close();
    this.bridgeServer.close();
    this.tunService?.destroy();
  }

  private startKernel() {
    let cfgStr = JSON.stringify(this.config);
    if (!easytier.parseNetworkConfig(cfgStr) || !easytier.runNetworkInstance(cfgStr)) {
      Logger.error("Failed to start git_core kernel", "EasyTierAbility");
      stopRuntimeStatsRecording()
    } else {
      startRuntimeStatsRecording(this.context.filesDir)
    }
  }

  private stopKernel() {
    stopRuntimeStatsRecording()
    easytier.stopKernel(this.instance_id);
  }

  private startCollecting() {
    this.kernelSocketService.connect(this.socketFilesDir + '/' + KERNEL_SOCKET_NAME)
    this.timer = setInterval(() => {
      this.bridgeServer.forwardLogs(easytier.drainLogLines())
    }, 500);
  }
}
