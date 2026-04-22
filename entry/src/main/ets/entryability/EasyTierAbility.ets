import { vpnExtension, VpnExtensionAbility, socket, connection } from '@kit.NetworkKit';
import { Logger } from '../util/Logger';
import Want from '@ohos.app.ability.Want';
import { fileIo } from '@kit.CoreFileKit';
import { NetworkConfig, NetworkInstanceRunningInfo } from '../protobuf/api_manage';
import easytier, { KeyValuePair } from 'easytier-ohrs';
import easytier_release from 'easytier-release';
import entry from 'libentry.so';
import { buffer, JSON } from '@kit.ArkTS';
import { convertAddrToIp, stringArr2RouteArr } from '../util/Conversion';
import { deviceInfo, BusinessError } from '@kit.BasicServicesKit';
import { NetworkSegment } from '../class/NetworkSegment';
import { SafeSet } from '../util/SafeSet';

// 定义消息通信接口
interface VpnLogData {
  appLogs: string[];
  nmLogs: string[];
  ohLogs: string[];
}

interface VpnMessage {
  type: string;
  data: KeyValuePair[] | VpnLogData;
}

export default class EasyTierAbility extends VpnExtensionAbility {
  server: socket.LocalSocketServer | undefined
  connections: Set<socket.LocalSocketConnection> = new Set()
  vpnConnection: vpnExtension.VpnConnection | undefined
  timer: number | undefined
  
  // Instance state
  git_core: boolean = true
  config: NetworkConfig | undefined
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

  onCreate(want: Want): void {
    Logger.debug("VpnExtAbi create", "EasyTierAbility")
    if (want.parameters == undefined) return;
    this.setupServer(want.parameters["socket"] as string);
    this.startCollecting();
    this.git_core = want.parameters["git_core"] as boolean;
    this.config = JSON.parse(want.parameters["cfg"] as string) as NetworkConfig;
    this.instance_id = this.config.instance_id!!;
    this.needTUN = !this.config.no_tun;
    this.vpn_routes = want.parameters["vpn_routes"] as boolean ?? false;
    this.white_list = want.parameters["white_list"] as boolean ?? false;
    this.black_list = want.parameters["black_list"] as string[] ?? [];
    this.dns = want.parameters["dns"] as string ?? "";
    this.dev = want.parameters["dev"] as boolean ?? false;
    this.force_global = want.parameters["force_global"] as boolean ?? true;
    this.show_log = want.parameters["show_log"] as boolean ?? false;
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
    this.startKernel();
  }

  onDestroy(): void {
    Logger.debug("VpnExtAbi destroy", "EasyTierAbility")
    if (this.timer) {
      clearInterval(this.timer);
    }
    this.stopKernel();
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
      easytier.stopNetworkInstance([this.instance_id]);
    } else {
      easytier_release.stopNetworkInstance([this.instance_id]);
    }
  }

  private startCollecting() {
    this.timer = setInterval(() => {
      // Collect Infos - 始终广播，即使是空的，以便主进程感知停止状态
      let infos = this.git_core ? easytier.collectNetworkInfos() : easytier_release.collectNetworkInfos();
      const infoMsg: VpnMessage = { type: "info", data: infos || [] };
      this.broadcast(infoMsg);
      if (infos && infos.length > 0) {
        this.processNetworkInfosForTun(infos);
      }

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

  private processNetworkInfosForTun(infos: KeyValuePair[]) {
    for (const info of infos) {
      if (info.key !== this.instance_id) continue;
      
      let newInfo: NetworkInstanceRunningInfo;
      try {
        newInfo = JSON.parse(info.value) as NetworkInstanceRunningInfo;
      } catch (e) {
        continue;
      }

      if (this.needTUN && newInfo.my_node_info?.virtual_ipv4?.address) {
        this.needTUN = false;
        this.setupTun(newInfo);
      } else if (!this.needTUN && (this.vpn_routes || deviceInfo.sdkApiVersion >= 20)) {
        this.updateRoutesIfNeeded(newInfo);
      }
    }
  }

  private setupTun(newInfo: NetworkInstanceRunningInfo) {
    let ip = convertAddrToIp(newInfo.my_node_info!!.virtual_ipv4!!.address!!.addr);
    let mask = newInfo.my_node_info!!.virtual_ipv4!!.network_length;
    let magicDNS = this.config?.enable_magic_dns ?? false;
    let needExitNode = (this.config?.exit_nodes ?? []).length > 0;

    Logger.info(`Setting up TUN for ${ip}/${mask}`, "EasyTierAbility");

    // Recalculate routes
    this.tunRoutes.clear();
    this.config?.routes.forEach((r) => {
      this.tunRoutes.add(new NetworkSegment(r))
    });
    this.tunRoutes.add(new NetworkSegment(`${ip}/${mask}`));
    
    newInfo.routes.forEach(route => {
      route.proxy_cidrs.forEach(cidr => this.addTunRoute(cidr));
      if (route.ipv4_addr?.address) {
        this.addTunRoute(convertAddrToIp(route.ipv4_addr.address.addr) + "/" + route.ipv4_addr.network_length);
      }
    });

    let appList = [
      deviceInfo.sdkApiVersion >= 22 ? "" : "top.frankhan.easytier",
      ...this.black_list
    ];

    let routesArr: NetworkSegment[] = [];
    this.tunRoutes.forEach(r => routesArr.push(r));

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
    }
    Logger.debug("VpnConfig: "+JSON.stringify(vpnConfig, undefined, 2), "EasyTierAbility")

    this.vpnConnection.create(vpnConfig).then((fd) => {
      if (this.git_core) {
        easytier.setTunFd(this.instance_id, fd);
      } else {
        easytier_release.setTunFd(this.instance_id, fd);
      }
    }).catch((err: Error) => {
      Logger.error(`vpnConnection create failed: ${JSON.stringify(err)}`, "EasyTierAbility");
    });
  }

  private updateRoutesIfNeeded(newInfo: NetworkInstanceRunningInfo) {
    let needUpdate = false;
    newInfo.routes.forEach(route => {
      route.proxy_cidrs.forEach(cidr => {
        needUpdate = this.addTunRoute(cidr) || needUpdate;
      });
      if (route.ipv4_addr?.address) {
        needUpdate = this.addTunRoute(convertAddrToIp(route.ipv4_addr.address.addr) + "/" + route.ipv4_addr.network_length) || needUpdate;
      }
    });

    if (needUpdate) {
      this.setupTun(newInfo);
    }
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
