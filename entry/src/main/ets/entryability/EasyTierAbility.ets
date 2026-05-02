import { vpnExtension, VpnExtensionAbility, socket, connection } from '@kit.NetworkKit';
import { Logger } from '../util/Logger';
import Want from '@ohos.app.ability.Want';
import { fileIo } from '@kit.CoreFileKit';
import easytier from 'easytier-ohrs';
import entry from 'libentry.so';
import { buffer, JSON } from '@kit.ArkTS';
import { convertAddrToIp, mergeRouteStrings, stringArr2RouteArr } from '../util/Conversion';
import { deviceInfo, BusinessError } from '@kit.BasicServicesKit';
import { NetworkSegment } from '../class/NetworkSegment';
import { SafeSet } from '../util/SafeSet';
import { ConfigJson } from '../SchemaConfig';
import { RuntimeAggregateState, RuntimeInstanceState } from '../RuntimeTypes';

const easytier_release = easytier

const KERNEL_SOCKET_NAME = 'easytier-kernel.sock'

interface KernelSocketMessage {
  messageType: string;
  payloadJson: string;
}

interface TunRequestPayload {
  configId: string;
  instanceId: string;
  displayName: string;
  virtualIpv4?: string;
  virtualIpv4Cidr?: string;
  aggregatedRoutes: string[];
  magicDnsEnabled: boolean;
  needExitNode: boolean;
}

// 定义消息通信接口
interface VpnLogData {
  appLogs: string[];
  nmLogs: string[];
  ohLogs: string[];
}

interface VpnMessage {
  type: string;
  data: RuntimeAggregateState | VpnLogData;
}

export default class EasyTierAbility extends VpnExtensionAbility {
  server: socket.LocalSocketServer | undefined
  connections: Set<socket.LocalSocketConnection> = new Set()
  kernelClient: socket.LocalSocket | undefined
  kernelMessageBuffer: string = ''
  vpnConnection: vpnExtension.VpnConnection | undefined
  timer: number | undefined
  
  // Instance state
  git_core: boolean = true
  config: ConfigJson | undefined
  instance_id: string = ""
  needTUN: boolean = false
  tunRoutes: SafeSet<NetworkSegment> = new SafeSet()
  
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
    this.setupServer(want.parameters["socket"] as string);
    this.git_core = want.parameters["git_core"] as boolean;
    this.config = JSON.parse(want.parameters["cfg"] as string) as ConfigJson;
    this.instance_id = this.config.instance_id!!;
    this.needTUN = !this.config.no_tun;
    this.vpn_routes = want.parameters["vpn_routes"] as boolean ?? false;
    this.white_list = want.parameters["white_list"] as boolean ?? false;
    this.black_list = want.parameters["black_list"] as string[] ?? [];
    this.dns = want.parameters["dns"] as string ?? "";
    this.dev = want.parameters["dev"] as boolean ?? false;
    this.force_global = want.parameters["force_global"] as boolean ?? true;
    this.show_log = want.parameters["show_log"] as boolean ?? false;
    easytier.initConfigStore(this.context.filesDir)
    entry.hilogInit();
    easytier.hilogGlobalOptions(0, "fhl")
    easytier_release.hilogGlobalOptions(0, "fhl")
    if (this.git_core) {
      easytier.initPanicHook();
    } else {
      easytier_release.initPanicHook();
    }

    if (this.show_log) {
      if (this.git_core) {
        easytier.initTracingSubscriber();
      } else {
        easytier_release.initTracingSubscriber();
      }
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
    let sandboxPath: string = this.context.filesDir + '/' + socketName;
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
      this.connections.add(connection);
      connection.on('error', (err: Object) => {
        Logger.error(`Connection error: ${JSON.stringify(err)}`, "EasyTierAbility");
        this.connections.delete(connection);
      });
      connection.on('close', () => {
        this.connections.delete(connection);
      });
    });
  }

  private startKernel() {
    let cfgStr = JSON.stringify(this.config);
    if (this.git_core) {
      if (!easytier.parseNetworkConfig(cfgStr) || !easytier.runNetworkInstance(cfgStr)) {
        Logger.error("Failed to start git_core kernel", "EasyTierAbility");
      }
    } else {
      if (!easytier_release.parseNetworkConfig(cfgStr) || !easytier_release.runNetworkInstance(cfgStr)) {
        Logger.error("Failed to start release kernel", "EasyTierAbility");
      }
    }
  }

  private stopKernel() {
    if (this.git_core) {
      easytier.stopKernel(this.instance_id);
    } else {
      easytier_release.stopNetworkInstance([this.instance_id]);
    }
  }

  private startCollecting() {
    this.connectToKernelSocket(this.context.filesDir + '/' + KERNEL_SOCKET_NAME)
    this.timer = setInterval(() => {
      // Collect Logs
      let appLogs = entry.getAppLog();
      let nmLogs = entry.getNetworkManagerLog();
      let ohLogs = entry.getOHLog();
      const logData: VpnLogData = { appLogs, nmLogs, ohLogs };
      const logMsg: VpnMessage = { type: "logs", data: logData };
      this.broadcast(logMsg);
    }, 100);
  }

  private broadcast(msg: VpnMessage) {
    let str = JSON.stringify(msg);
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
        this.kernelMessageBuffer += buffer.from(value.message).toString()
        const messages = this.kernelMessageBuffer.split('\n')
        this.kernelMessageBuffer = messages.pop() ?? ''
        for (const rawMessage of messages) {
          if (rawMessage.length === 0) {
            continue
          }
          const msg = JSON.parse(rawMessage) as KernelSocketMessage
          if (msg.messageType === 'runtime_snapshot') {
            const snapshot = JSON.parse(msg.payloadJson) as RuntimeAggregateState
            this.broadcast({ type: 'runtime_snapshot', data: snapshot })
            this.processSnapshotForTun(snapshot)
          } else if (msg.messageType === 'tun_request') {
            const payload = JSON.parse(msg.payloadJson) as TunRequestPayload
            Logger.info(`received tun_request instance=${payload.instanceId} cidr=${payload.virtualIpv4Cidr ?? ''} ipv4=${payload.virtualIpv4 ?? ''} routes=${JSON.stringify(payload.aggregatedRoutes)}`, "EasyTierAbility")
            this.setupTunFromPayload(payload)
          }
        }
      } catch (e) {
        Logger.error(`kernel socket message error: ${JSON.stringify(e)}`, "EasyTierAbility")
      }
    })
  }

  private processSnapshotForTun(snapshot: RuntimeAggregateState): void {
    const instance = (snapshot.instances ?? []).find((value: RuntimeInstanceState) => value.instanceId === this.instance_id)
    if (!instance) {
      Logger.info(`processSnapshotForTun missing instance=${this.instance_id}`, "EasyTierAbility")
      return
    }
    Logger.info(`processSnapshotForTun instance=${this.instance_id} needTUN=${this.needTUN} tunAttached=${instance.tunAttached} tunRequired=${instance.tunRequired} ipv4=${instance.myNodeInfo?.virtualIpv4 ?? ''} cidr=${instance.myNodeInfo?.virtualIpv4Cidr ?? ''}`, "EasyTierAbility")
    if (this.needTUN && instance.myNodeInfo?.virtualIpv4Cidr && instance.myNodeInfo?.virtualIpv4) {
      this.needTUN = false
      const mask = Number(instance.myNodeInfo.virtualIpv4Cidr.split('/')[1] ?? '24')
      this.setupTunWithRoutes(
        instance.myNodeInfo.virtualIpv4,
        mask,
        instance.magicDnsEnabled,
        instance.needExitNode,
        snapshot.tun.aggregatedRoutes,
      )
      return
    }
    this.updateRoutesFromSnapshot(snapshot)
  }

  private updateRoutesFromSnapshot(snapshot: RuntimeAggregateState): void {
    if (!(this.vpn_routes || deviceInfo.sdkApiVersion >= 20)) {
      return
    }
    const tun = snapshot.tun
    const attachedIds = tun?.attachedInstanceIds ?? []
    if (!tun?.active || attachedIds.indexOf(this.instance_id) < 0) {
      this.lastRoutesSignature = ''
      return
    }
    const instance = (snapshot.instances ?? []).find((value: RuntimeInstanceState) => value.instanceId === this.instance_id)
    const cidr = instance?.myNodeInfo?.virtualIpv4Cidr
    const ip = instance?.myNodeInfo?.virtualIpv4
    const aggregatedRoutes = tun?.aggregatedRoutes ?? []
    const routeSignature = JSON.stringify(aggregatedRoutes)
    if (!cidr || !ip || routeSignature === this.lastRoutesSignature) {
      return
    }
    this.lastRoutesSignature = routeSignature
    this.setupTunWithRoutes(ip, Number(cidr.split('/')[1] ?? '24'), instance?.magicDnsEnabled as boolean ?? false,
      instance?.needExitNode as boolean ?? false, aggregatedRoutes)
  }

  private setupTunFromPayload(payload: TunRequestPayload) {
    const cidr = payload.virtualIpv4Cidr ?? ''
    const ip = payload.virtualIpv4 ?? cidr.split('/')[0]
    const mask = Number(cidr.split('/')[1] ?? '24')
    this.setupTunWithRoutes(ip, mask, payload.magicDnsEnabled, payload.needExitNode, payload.aggregatedRoutes)
  }

  private setupTunWithRoutes(ip: string, mask: number, magicDNS: boolean, needExitNode: boolean, routes: string[]) {
    Logger.info(`Setting up TUN for ${ip}/${mask}`, "EasyTierAbility");

    let appList = [
      deviceInfo.sdkApiVersion >= 22 ? "" : "top.frankhan.easytier",
      ...this.black_list
    ];

    const configRoutes = (this.config?.routes as string[] | undefined) ?? []
    const mergedRoutes = mergeRouteStrings(routes, configRoutes)
    let routesArr: NetworkSegment[] = [];
    mergedRoutes.forEach((route) => {
      try {
        routesArr.push(new NetworkSegment(route))
      } catch (_) {
      }
    })

    let vpnConfig: vpnExtension.VpnConfig = {
      addresses: [{ address: { address: ip, family: 1 }, prefixLength: mask }],
      blockedApplications: this.white_list ? [] : appList,
      trustedApplications: this.white_list ? appList : [],
      dnsAddresses: magicDNS ? ["100.100.100.101"] : (this.dev ? [this.dns || "223.5.5.5"] : ["223.5.5.5"]),
      mtu: 1380,
      routes: stringArr2RouteArr(ip, magicDNS, needExitNode, routesArr, this.force_global)
    };

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

  private addTunRoute(route: string): boolean {
    let result = true;
    this.tunRoutes.forEach(oldRoute => {
      result = !oldRoute.contains(route) && result;
    });
    if (result) {
      try {
        this.tunRoutes.add(new NetworkSegment(route));
      } catch (e) {
        return false;
      }
    }
    return result;
  }
}
