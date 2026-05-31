import { vpnExtension, VpnExtensionAbility, socket, connection } from '@kit.NetworkKit';
import { Logger } from '../shared/logging/Logger';
import Want from '@ohos.app.ability.Want';
import { fileIo } from '@kit.CoreFileKit';
import easytier from 'easytier-ohrs';
import entry from 'libentry.so';
import { buffer, JSON } from '@kit.ArkTS';
import { stringArr2RouteArr } from '../util/Conversion';
import { NetworkSegment } from '../models/network/NetworkSegment';
import { deviceInfo, BusinessError } from '@kit.BasicServicesKit';
import { ConfigJson } from '../config/schema/SchemaConfig';
import { KERNEL_SOCKET_NAME, TunRequestPayload, VpnContinueStateData, VpnLogData, VpnMessage, VpnSnapshotSubscriptionData } from '../infrastructure/bridge/kernel/KernelBridgeTypes'
import { buildVpnRuntimeSnapshotMessage, decodeSocketChunk, isRuntimeSnapshotMessage, parseKernelSocketMessage, parseVpnBridgeMessage } from '../infrastructure/bridge/kernel/SocketCodec'
import { routeSignature } from '../infrastructure/bridge/kernel/RouteStore'
import { startRuntimeStatsRecording, stopRuntimeStatsRecording } from '../services/runtime/RuntimeStatsService'
import { AppManager } from '../AppManager'

export default class EasyTierAbility extends VpnExtensionAbility {
  server: socket.LocalSocketServer | undefined
  connections: Map<number, socket.LocalSocketConnection> = new Map()
  kernelClient: socket.LocalSocket | undefined
  kernelMessageBuffer: string = ''
  bridgeMessageBuffers: Map<number, string> = new Map()
  vpnConnection: vpnExtension.VpnConnection | undefined
  timer: number | undefined
  config: ConfigJson | undefined
  instance_id: string = ""
  needTUN: boolean = false
  socketFilesDir: string = ''
  
  // Preferences passed from UI
  vpn_routes: boolean = false
  white_list: boolean = false
  black_list: string[] = []
  dns: string = ""
  dev: boolean = false
  force_global: boolean = true
  show_log: boolean = false
  lastRoutesSignature: string = ""
  private tunCreateSeq: number = 0
  private lastTunTrigger: string = ""
  private continuationActive: boolean = false
  private snapshotSubscribers: Set<number> = new Set()

  private shouldProtectProcessNet(): boolean {
    return deviceInfo.sdkApiVersion >= 22 && this.force_global && (this.config?.exit_nodes?.length ?? 0) > 0
  }

  private async prepareVpnProtection(): Promise<void> {
    if (!this.shouldProtectProcessNet()) {
      return
    }
    if (!this.vpnConnection) {
      this.vpnConnection = vpnExtension.createVpnConnection(this.context)
      Logger.debug("vpnConnection created for process protection", "EasyTierAbility")
    }
    await this.vpnConnection.protectProcessNet()
    Logger.info("protectProcessNet completed before kernel start", "EasyTierAbility")
  }

  onCreate(want: Want): void {
    Logger.debug("VpnExtAbi create", "EasyTierAbility")
    if (want.parameters == undefined) return;
    const cfgParam = want.parameters["cfg"] as string | undefined
    if (!cfgParam) {
      Logger.debug("VpnExtAbi create without cfg, likely permission probe", "EasyTierAbility")
      return
    }
    this.socketFilesDir = want.parameters["socket_files_dir"] as string ?? this.context.filesDir;
    this.setupServer(want.parameters["socket"] as string);
    this.config = JSON.parse(cfgParam) as ConfigJson;
    this.instance_id = this.config.instance_id!!;
    this.needTUN = !this.config.no_tun;
    this.vpn_routes = want.parameters["vpn_routes"] as boolean ?? false;
    this.white_list = want.parameters["white_list"] as boolean ?? false;
    this.black_list = want.parameters["black_list"] as string[] ?? [];
    this.dns = want.parameters["dns"] as string ?? "";
    this.dev = want.parameters["dev"] as boolean ?? false;
    this.force_global = want.parameters["force_global"] as boolean ?? true;
    this.show_log = want.parameters["show_log"] as boolean ?? false;
    easytier.initConfigStore(this.socketFilesDir)
    easytier.setKernelSnapshotEnabled(false)
    entry.hilogInit();
    easytier.hilogGlobalOptions(0, "fhl")
    easytier.initPanicHook();

    if (this.show_log) {
      easytier.initTracingSubscriber();
    }
    this.prepareVpnProtection().catch((err: Error) => {
      Logger.error(`protectProcessNet failed before kernel start: ${JSON.stringify(err)}`, "EasyTierAbility")
    }).finally(() => {
      this.startCollecting();
      this.startKernel();
    })
  }

  onDestroy(): void {
    Logger.debug("VpnExtAbi destroy", "EasyTierAbility")
    this.publishContinuationState(false)
    if (this.timer) {
      clearInterval(this.timer);
    }
    this.stopKernel();
    this.kernelClient?.close();
    this.server?.close();
    this.vpnConnection?.destroy();
  }

  private setupServer(socketName: string) {
    this.server = socket.constructLocalSocketServerInstance();
    let sandboxPath: string = this.socketFilesDir + '/' + socketName;
    try {
      fileIo.unlinkSync(sandboxPath);
    } catch (e) {}
    
    let listenAddr: socket.LocalAddress = {
      address: sandboxPath
    }
    this.server.listen(listenAddr).then(() => {
      Logger.debug(`VpnServer listening on ${sandboxPath}`, "EasyTierAbility")
    }).catch((err: object) => {
      Logger.error(`VpnServer listen error: ${JSON.stringify(err)}`, "EasyTierAbility")
    });

    this.server.on('connect', (connection: socket.LocalSocketConnection) => {
      Logger.debug("UI process connected to VpnServer", "EasyTierAbility")
      this.connections.set(connection.clientId, connection);
      this.sendBridgeMessage(connection, {
        type: 'continue_state',
        data: { active: this.continuationActive } as VpnContinueStateData
      })
      connection.on('error', (err: Object) => {
        Logger.error(`Connection error: ${JSON.stringify(err)}`, "EasyTierAbility");
        this.dropConnection(connection)
      });
      connection.on('message', (value: socket.LocalSocketMessageInfo) => {
        this.processBridgeMessage(connection, value.message)
      })
      connection.on('close', () => {
        this.dropConnection(connection)
      });
    });
  }

  private processBridgeMessage(connection: socket.LocalSocketConnection, message: ArrayBuffer | Uint8Array | string): void {
    try {
      const decoded = decodeSocketChunk(this.bridgeMessageBuffers.get(connection.clientId) ?? '', message)
      this.bridgeMessageBuffers.set(connection.clientId, decoded.rest)
      for (const rawMessage of decoded.messages) {
        const msg = parseVpnBridgeMessage(rawMessage)
        if (msg.type === 'snapshot_subscription') {
          const data = msg.data as VpnSnapshotSubscriptionData
          if (data.enabled) {
            this.snapshotSubscribers.add(connection.clientId)
          } else {
            this.snapshotSubscribers.delete(connection.clientId)
          }
          this.syncKernelSnapshotSubscription()
        }
      }
    } catch (error) {
      Logger.error(`VpnServer bridge message error: ${JSON.stringify(error)}`, "EasyTierAbility")
    }
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
    this.connectToKernelSocket(this.socketFilesDir + '/' + KERNEL_SOCKET_NAME)
    this.timer = setInterval(() => {
      if (this.connections.size === 0) {
        return
      }
      // Collect Logs
      let appLogs = entry.getAppLog();
      let nmLogs = entry.getNetworkManagerLog();
      const logData: VpnLogData = { appLogs, nmLogs };
      const logMsg: VpnMessage = { type: "logs", data: logData };
      this.broadcast(logMsg);
    }, 100);
  }

  private dropConnection(connection: socket.LocalSocketConnection): void {
    this.connections.delete(connection.clientId)
    this.bridgeMessageBuffers.delete(connection.clientId)
    this.snapshotSubscribers.delete(connection.clientId)
    this.syncKernelSnapshotSubscription()
  }

  private syncKernelSnapshotSubscription(): void {
    easytier.setKernelSnapshotEnabled(this.snapshotSubscribers.size > 0)
  }

  private sendBridgeMessage(connection: socket.LocalSocketConnection, msg: VpnMessage) {
    this.sendRawBridgeMessage(connection, JSON.stringify(msg) + '\n')
  }

  private sendRawBridgeMessage(connection: socket.LocalSocketConnection, rawMessage: string) {
    const uint8Array = buffer.from(rawMessage).buffer
    connection.send({ data: uint8Array }).catch((err: BusinessError) => {
      this.dropConnection(connection)
      if (err.code === 2301032) {
        Logger.debug("VpnServer peer disconnected: " + JSON.stringify(err), "EasyTierAbility")
      } else {
        Logger.error("Failed to send data to UI: " + JSON.stringify(err), "EasyTierAbility")
      }
    })
  }

  private broadcast(msg: VpnMessage) {
    this.connections.forEach(conn => {
      this.sendBridgeMessage(conn, msg)
    });
  }

  private broadcastRaw(rawMessage: string) {
    this.connections.forEach(conn => {
      this.sendRawBridgeMessage(conn, rawMessage)
    });
  }

  private publishContinuationState(active: boolean): void {
    this.continuationActive = active
    this.broadcast({
      type: 'continue_state',
      data: { active } as VpnContinueStateData
    })
  }

  private connectToKernelSocket(socketPath: string) {
    this.kernelClient?.close()
    this.kernelClient = socket.constructLocalSocketInstance()
    const address: socket.LocalConnectOptions = {
      address: {
        address: socketPath
      }
    }

    let retryCount = 0
    const connect = () => {
      this.kernelClient?.connect(address).then(() => {
        Logger.info("Connected to kernel socket", "EasyTierAbility")
      }).catch(() => {
        if (retryCount < 20) {
          retryCount++
          setTimeout(connect, 500)
        }
      })
    }
    setTimeout(connect, 200)

    this.kernelClient.on('message', (value: socket.LocalSocketMessageInfo) => {
      try {
        const decoded = decodeSocketChunk(this.kernelMessageBuffer, value.message)
        this.kernelMessageBuffer = decoded.rest
        for (const rawMessage of decoded.messages) {
          if (isRuntimeSnapshotMessage(rawMessage)) {
            if (this.connections.size > 0) {
              this.broadcastRaw(buildVpnRuntimeSnapshotMessage(rawMessage))
            }
            continue
          }
          const msg = parseKernelSocketMessage(rawMessage)
          if (msg.messageType === 'tun_request') {
            const payload = typeof msg.payloadJson === 'string' ? JSON.parse(msg.payloadJson) as TunRequestPayload : msg.payloadJson as TunRequestPayload
            this.lastTunTrigger = 'tun_request'
            Logger.info(`kernel tun_request trigger instance=${this.instance_id} cidr=${payload.virtualIpv4Cidr ?? ''} sig=${routeSignature(payload.aggregatedRoutes ?? [])}`, "EasyTierAbility")
            this.setupTunFromPayload(payload)
          }
        }
      } catch (e) {
        Logger.error(`kernel socket message error: ${JSON.stringify(e)}`, "EasyTierAbility")
      }
    })
  }

  private setupTunFromPayload(payload: TunRequestPayload) {
    this.needTUN = false
    const cidr = payload.virtualIpv4Cidr ?? ''
    const ip = payload.virtualIpv4 ?? cidr.split('/')[0]
    const mask = Number(cidr.split('/')[1] ?? '24')
    const routes = payload.aggregatedRoutes ?? []
    this.lastRoutesSignature = routeSignature(routes)
    Logger.debug(`setupTunFromPayload instance=${this.instance_id} trigger=${this.lastTunTrigger} sig=${this.lastRoutesSignature} cidr=${cidr} ip=${ip} routes=${JSON.stringify(routes)}`, "EasyTierAbility")
    this.setupTunWithRoutes(ip, mask, payload.magicDnsEnabled, payload.needExitNode, routes)
  }

  private async setupTunWithRoutes(ip: string, mask: number, magicDNS: boolean, needExitNode: boolean, routes: string[]) {
    this.tunCreateSeq++
    Logger.info(`Setting up TUN #${this.tunCreateSeq} for ${ip}/${mask} trigger=${this.lastTunTrigger} sig=${this.lastRoutesSignature}`, "EasyTierAbility");

    let appList = [
      deviceInfo.sdkApiVersion >= 22 ? "" : "top.frankhan.easytier",
      ...this.black_list
    ];

    Logger.debug(`setupTunWithRoutes routes kernel=${JSON.stringify(routes)}`, "EasyTierAbility")
    let routesArr: NetworkSegment[] = [];
    routes.forEach((route) => {
      try {
        routesArr.push(new NetworkSegment(route))
      } catch (_) {
      }
    })
    Logger.debug(`setupTunWithRoutes parsedRoutes=${JSON.stringify(routesArr.map((route) => route.networkAddress + '/' + route.prefix))}`, "EasyTierAbility")

    let vpnConfig: vpnExtension.VpnConfig = {
      addresses: [{ address: { address: ip, family: 1 }, prefixLength: mask }],
      blockedApplications: this.white_list ? [] : appList,
      trustedApplications: this.white_list ? appList : [],
      dnsAddresses: magicDNS ? ["100.100.100.101"] : (this.dev ? [this.dns || "223.5.5.5"] : ["223.5.5.5"]),
      mtu: 1380,
      routes: stringArr2RouteArr(ip, magicDNS, needExitNode, routesArr, this.force_global)
    };
    Logger.debug(`setupTunWithRoutes finalVpnRoutes=${JSON.stringify(vpnConfig.routes ?? [])}`, "EasyTierAbility")

    if (!this.vpnConnection) {
      this.vpnConnection = vpnExtension.createVpnConnection(this.context);
      Logger.debug("vpnConnection created in EasyTierAbility", "EasyTierAbility")
    }
    Logger.debug("VpnConfig: "+JSON.stringify(vpnConfig, undefined, 2), "EasyTierAbility")

    Logger.info(`setupTunWithRoutes calling create seq=${this.tunCreateSeq} trigger=${this.lastTunTrigger}`, "EasyTierAbility")
    await this.vpnConnection.destroy()
    this.vpnConnection.create(vpnConfig).then((fd) => {
      Logger.info(`vpnConnection.create success instance=${this.instance_id} fd=${fd} seq=${this.tunCreateSeq} trigger=${this.lastTunTrigger}`, "EasyTierAbility")
      this.publishContinuationState(true)
      easytier.setTunFd(this.instance_id, fd);
      Logger.debug(`setTunFd sent instance=${this.instance_id}`, "EasyTierAbility")
    }).catch((err: Error) => {
      this.publishContinuationState(false)
      Logger.error(`vpnConnection create failed: ${JSON.stringify(err)}`, "EasyTierAbility");
    });
  }
}
