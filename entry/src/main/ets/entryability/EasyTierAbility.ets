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
import { RuntimeAggregateState, RuntimeInstanceState } from '../types/runtime/RuntimeTypes';
import { KERNEL_SOCKET_NAME, TunRequestPayload, VpnLogData, VpnMessage } from '../infrastructure/bridge/kernel/KernelBridgeTypes'
import { decodeSocketChunk, parseKernelSocketMessage } from '../infrastructure/bridge/kernel/SocketCodec'
import { routeSignature } from '../infrastructure/bridge/kernel/RouteStore'

export default class EasyTierAbility extends VpnExtensionAbility {
  server: socket.LocalSocketServer | undefined
  connections: Map<number, socket.LocalSocketConnection> = new Map()
  kernelClient: socket.LocalSocket | undefined
  kernelMessageBuffer: string = ''
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
    entry.hilogInit();
    easytier.hilogGlobalOptions(0, "fhl")
    easytier.initPanicHook();

    if (this.show_log) {
      easytier.initTracingSubscriber();
    }
    this.startCollecting();
    this.startKernel();
  }

  onDestroy(): void {
    Logger.debug("VpnExtAbi destroy", "EasyTierAbility")
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
      connection.on('error', (err: Object) => {
        Logger.error(`Connection error: ${JSON.stringify(err)}`, "EasyTierAbility");
        this.connections.delete(connection.clientId);
      });
      connection.on('close', () => {
        this.connections.delete(connection.clientId);
      });
    });
  }

  private startKernel() {
    let cfgStr = JSON.stringify(this.config);
    if (!easytier.parseNetworkConfig(cfgStr) || !easytier.runNetworkInstance(cfgStr)) {
      Logger.error("Failed to start git_core kernel", "EasyTierAbility");
    }
  }

  private stopKernel() {
    easytier.stopKernel(this.instance_id);
  }

  private startCollecting() {
    this.connectToKernelSocket(this.socketFilesDir + '/' + KERNEL_SOCKET_NAME)
    this.timer = setInterval(() => {
      // Collect Logs
      let appLogs = entry.getAppLog();
      let nmLogs = entry.getNetworkManagerLog();
      const logData: VpnLogData = { appLogs, nmLogs };
      const logMsg: VpnMessage = { type: "logs", data: logData };
      this.broadcast(logMsg);
    }, 100);
  }

  private broadcast(msg: VpnMessage) {
    let str = JSON.stringify(msg) + '\n';
    let uint8Array = buffer.from(str).buffer
    this.connections.forEach(conn => {
      conn.send({ data: uint8Array }).catch((err: BusinessError) => {
        Logger.error("Failed to send data to UI: " + JSON.stringify(err), "EasyTierAbility");
      });
    });
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
          const msg = parseKernelSocketMessage(rawMessage)
          if (msg.messageType === 'runtime_snapshot') {
            const snapshot = JSON.parse(msg.payloadJson) as RuntimeAggregateState
            this.broadcast({ type: 'runtime_snapshot', data: snapshot })
            if (!this.needTUN && (this.vpn_routes || deviceInfo.sdkApiVersion >= 20)) {
              this.updateRoutesFromSnapshot(snapshot)
            }
          } else if (msg.messageType === 'tun_request') {
            const payload = JSON.parse(msg.payloadJson) as TunRequestPayload
            this.setupTunFromPayload(payload)
          }
        }
      } catch (e) {
        Logger.error(`kernel socket message error: ${JSON.stringify(e)}`, "EasyTierAbility")
      }
    })
  }

  private updateRoutesFromSnapshot(snapshot: RuntimeAggregateState): void {
    if (!(this.vpn_routes || deviceInfo.sdkApiVersion >= 20)) {
      return
    }
    const tun = snapshot.tun
    const attachedIds = tun?.attachedInstanceIds ?? []
    if (!tun?.active || attachedIds.indexOf(this.instance_id) < 0) {
      return
    }
    const instance = (snapshot.instances ?? []).find((value: RuntimeInstanceState) => value.instanceId === this.instance_id)
    const cidr = instance?.myNodeInfo?.virtualIpv4Cidr
    const ip = instance?.myNodeInfo?.virtualIpv4
    const routes = tun?.aggregatedRoutes ?? []
    const currentSignature = routeSignature(routes)
    if (!cidr || !ip || currentSignature === this.lastRoutesSignature) {
      return
    }
    this.lastRoutesSignature = currentSignature
    this.setupTunWithRoutes(ip, Number(cidr.split('/')[1] ?? '24'), instance?.magicDnsEnabled as boolean ?? false,
      instance?.needExitNode as boolean ?? false, routes)
  }

  private setupTunFromPayload(payload: TunRequestPayload) {
    this.needTUN = false
    const cidr = payload.virtualIpv4Cidr ?? ''
    const ip = payload.virtualIpv4 ?? cidr.split('/')[0]
    const mask = Number(cidr.split('/')[1] ?? '24')
    const routes = payload.aggregatedRoutes ?? []
    this.lastRoutesSignature = routeSignature(routes)
    this.setupTunWithRoutes(ip, mask, payload.magicDnsEnabled, payload.needExitNode, routes)
  }

  private setupTunWithRoutes(ip: string, mask: number, magicDNS: boolean, needExitNode: boolean, routes: string[]) {
    Logger.info(`Setting up TUN for ${ip}/${mask}`, "EasyTierAbility");

    let appList = [
      deviceInfo.sdkApiVersion >= 22 ? "" : "top.frankhan.easytier",
      ...this.black_list
    ];

    Logger.info(`setupTunWithRoutes routes kernel=${JSON.stringify(routes)}`, "EasyTierAbility")
    let routesArr: NetworkSegment[] = [];
    routes.forEach((route) => {
      try {
        routesArr.push(new NetworkSegment(route))
      } catch (_) {
      }
    })
    Logger.info(`setupTunWithRoutes parsedRoutes=${JSON.stringify(routesArr.map((route) => route.networkAddress + '/' + route.prefix))}`, "EasyTierAbility")

    let vpnConfig: vpnExtension.VpnConfig = {
      addresses: [{ address: { address: ip, family: 1 }, prefixLength: mask }],
      blockedApplications: this.white_list ? [] : appList,
      trustedApplications: this.white_list ? appList : [],
      dnsAddresses: magicDNS ? ["100.100.100.101"] : (this.dev ? [this.dns || "223.5.5.5"] : ["223.5.5.5"]),
      mtu: 1380,
      routes: stringArr2RouteArr(ip, magicDNS, needExitNode, routesArr, this.force_global)
    };
    Logger.info(`setupTunWithRoutes finalVpnRoutes=${JSON.stringify(vpnConfig.routes ?? [])}`, "EasyTierAbility")

    if (!this.vpnConnection) {
      this.vpnConnection = vpnExtension.createVpnConnection(this.context);
      Logger.info("vpnConnection created in EasyTierAbility", "EasyTierAbility")
    }
    Logger.debug("VpnConfig: "+JSON.stringify(vpnConfig, undefined, 2), "EasyTierAbility")

    this.vpnConnection.create(vpnConfig).then((fd) => {
      Logger.info(`vpnConnection.create success instance=${this.instance_id} fd=${fd}`, "EasyTierAbility")
      easytier.setTunFd(this.instance_id, fd);
      Logger.info(`setTunFd sent instance=${this.instance_id}`, "EasyTierAbility")
    }).catch((err: Error) => {
      Logger.error(`vpnConnection create failed: ${JSON.stringify(err)}`, "EasyTierAbility");
    });
  }
}
