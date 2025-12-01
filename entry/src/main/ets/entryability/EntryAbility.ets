import { Configuration, UIAbility, Want, WantAgent, wantAgent } from "@kit.AbilityKit";
import { backgroundTaskManager } from "@kit.BackgroundTasksKit";
import { geoLocationManager } from "@kit.LocationKit";
import { window } from "@kit.ArkUI";
import { EventHelper } from "../util/EventHelper";
import { Logger, LogLocate } from "../util/Logger";
import { BusinessError, deviceInfo, emitter } from "@kit.BasicServicesKit";
import easytier from "easytier-ohrs"
import { vpnExtension } from "@kit.NetworkKit";
import Manager from "../Manager";
import { objectToHomoTOML, stringArr2RouteArr } from "../util/Conversion";
import { readConfig } from "../util/Compress";
import { url } from "@kit.ArkTS";
import entry from 'libentry.so'
import { BUILD_TIME } from "../util/info/BuildTime";
import { SpiderMan } from "@simplepeng/spider-man";
import { WindowUtil } from "../WindowUtil";
import { HMRouterMgr } from "@hadss/hmrouter";
import { AppManager } from "../AppManager";
import { HMRouterTransitions } from "@hadss/hmrouter-transitions";
import { DialogHub } from "@hadss/dialoghub";
import { sendToast } from "../ToastUtil";
import { isIpAddr } from "../class/config/IP";

@LogLocate("EntryAbility")
export default class EntryAbility extends UIAbility {
  vpnConnection: vpnExtension.VpnConnection | undefined

  startContinuousTask(cfg: string) {
    if (!AppManager.permission.isGetLocPerm() || !canIUse("SystemCapability.ResourceSchedule.BackgroundTaskManager.ContinuousTask")) {
      if (easytier.runNetworkInstance(cfg)) {
        sendToast("实例启动成功", $r("sys.symbol.wifi"))
      }else {
        sendToast("实例启动失败, 可能是内核错误, 请上报日志.", $r("sys.symbol.exclamationmark_circle"), 1)
        Logger.error("启动失败", this)
      }
      return
    }
    Logger.info("[EntryAbi] start background alive")
    let wantAgentInfo: wantAgent.WantAgentInfo = {
      wants: [
        {
          bundleName: "top.frankhan.easytier",
          abilityName: "EntryAbility"
        }
      ],
      actionType: wantAgent.OperationType.START_ABILITY,
      requestCode: 0,
      actionFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
    };
    let request: geoLocationManager.ContinuousLocationRequest =
      { 'interval': 5, 'locationScenario': geoLocationManager.UserActivityScenario.NAVIGATION };
    try {
      wantAgent.getWantAgent(wantAgentInfo).then((wantAgentObj: WantAgent) => {
        try {
          backgroundTaskManager.startBackgroundRunning(this.context, ["location"], wantAgentObj).then(() => {
            if (easytier.runNetworkInstance(cfg)) {
              sendToast("实例启动成功", $r("sys.symbol.wifi"))
              geoLocationManager.on('locationChange', request, () => {
                Logger.debug("GeoLoc alive", this)
              });
            }else {
              sendToast("实例启动失败, 可能是内核错误, 请上报日志.", $r("sys.symbol.exclamationmark_circle"), 1)
              Logger.error("启动失败", this)
              this.stopContinuousTask()
            }
          }).catch(() => {});
        } catch (error) {}
      });
    } catch (error) {}
  }

  stopContinuousTask() {
    if (!canIUse("SystemCapability.ResourceSchedule.BackgroundTaskManager.ContinuousTask")) return;
    Logger.info("stop background alive", this)
    geoLocationManager.off("locationChange")
    backgroundTaskManager.stopBackgroundRunning(this.context).then(() => {
      this.vpnConnection?.destroy()
    }).catch(() => {});
  }

  onCreate(want: Want) {
    HMRouterMgr.openLog("INFO")
    HMRouterMgr.init({
      context: this.context
    })
    entry.hilogInit()
    easytier.hilogGlobalOptions(0,"fhl")
    easytier.initPanicHook()
    Logger.info("BuildTime:"+BUILD_TIME, this)
    this.start_bg_Listener()
    this.stop_bg_Listener()
    this.setup_tun_Listener()
    this.readSharedData(want)
  }

  onNewWant(want: Want) {
    Logger.debug("onNetWant", this)
    this.readSharedData(want)
  }

  readSharedData(want: Want) {
    let uri = want.uri;
    if (uri) {
      Logger.info("get uri:"+uri, this)
      try {
        let urlObject = url.URL.parseURL(uri);
        let cfg = urlObject.params.get("cfg")
        if (cfg) {
          readConfig(cfg)
        }
      } catch (err) {
        let error = err as BusinessError;
        Logger.error(`readSharedData error, code: ${error.code}, mesage: ${error.message}`, this);
      }
    }
  }

  onDestroy() {
    Logger.debug("onDestroy", this)
    this.stopContinuousTask()
  }

  start_bg_Listener() {
    Logger.debug("start_bg_Listener", this)
    EventHelper.emitterListener("start_bg",(data) => {
      this.prepare_vpn(() => {
        Logger.info("start_bg_task", this)
        this.startContinuousTask(data.data!.cfg);
      })
    })
  }

  stop_bg_Listener() {
    Logger.debug("stop_bg_Listener", this)
    EventHelper.emitterListener("stop_bg",() => {
      Logger.info("stop_bg_task", this)
      this.stopContinuousTask()
    })
  }

  setup_tun_Listener() {
    Logger.debug("setup_tun_Listener", this)
    EventHelper.emitterListener("setup_tun", (data) => {
      Logger.info("setup_tun", this)
      let ip = data.data!.ip as string
      let mask = data.data!.mask as number
      let magicDNS = data.data!.magicDNS as boolean
      let inst_id = data.data!.id as string
      let needExitNode = data.data!.needExitNode as boolean
      this.setup_tun(ip, mask, magicDNS, inst_id, needExitNode)
    })
    let restart = (data: emitter.EventData) => {
      this.vpnConnection?.destroy().catch(() => {
      }).then(() => {
        let ip = data.data!.ip as string
        let mask = data.data!.mask as number
        let magicDNS = data.data!.magicDNS as boolean
        let inst_id = data.data!.id as string
        let needExitNode = data.data!.needExitNode as boolean
        this.setup_tun(ip, mask, magicDNS, inst_id, needExitNode)
      })
    }
    EventHelper.emitterListener("update_route", (data) => {
      Logger.info("update_route", this)
      restart(data)
    })
    EventHelper.emitterListener("change_ipv4", (data) => {
      Logger.info("change_ipv4", this)
      restart(data)
    })
  }

  safeDns(): string {
    if (isIpAddr(AppManager.preference.dns)) {
      return AppManager.preference.dns
    }else {
      return "223.5.5.5"
    }
  }

  setup_tun(ip: string, mask: number, magicDNS: boolean, inst_id: string, needExitNode: boolean) {
    Logger.debug("[EntryAbi] 当前IP:"+ip)
    Logger.debug("[EntryAbi] 当前路由表:"+Array.from(AppManager.easytier.tunRoutes).join(","))
    let vpnConfig: vpnExtension.VpnConfig = AppManager.preference.vpn_routes || deviceInfo.sdkApiVersion >= 20?{
      addresses: [
        {
          address: {
            address:ip,
            family:1,
          },
          prefixLength:mask
        }
      ],
      blockedApplications: [
        "top.frankhan.easytier"
      ],
      trustedApplications: [],
      dnsAddresses: magicDNS?["100.100.100.101"]:(AppManager.preference.dev?[this.safeDns()]:["223.5.5.5"]),
      mtu: 1380,
      routes: stringArr2RouteArr(ip, magicDNS, needExitNode)
    }:{
      addresses: [
        {
          address: {
            address:ip,
            family:1,
          },
          prefixLength:mask
        }
      ],
      blockedApplications: [
        "top.frankhan.easytier"
      ],
      trustedApplications: [],
      dnsAddresses: magicDNS?["100.100.100.101"]:(AppManager.preference.dev?[this.safeDns()]:["223.5.5.5"]),
      mtu: 1380
    }
    if (this.vpnConnection === undefined) {
      Logger.error("[EntryAbi] vpnConnection not found")
    }
    Logger.debug("[EntryAbi] VPN配置:"+JSON.stringify(vpnConfig))
    this.vpnConnection!.create(vpnConfig).then((fd) => {
      easytier.setTunFd(inst_id, fd)
    })
  }

  prepare_vpn(callback: () => void = () => {}) {
    if (this.vpnConnection !== undefined) {
      callback()
      return;
    }
    Logger.info("prepare vpn", this)
    AppManager.permission.requestVpnPerm(() => {
      this.vpnConnection = vpnExtension.createVpnConnection(getContext(this) as vpnExtension.VpnExtensionContext)
      callback()
    })
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    SpiderMan.init();
    HMRouterTransitions.init(windowStage);
    windowStage.getMainWindowSync().on('windowSizeChange', (data) => {
      WindowUtil.update(data.width, data.height)
    });
    windowStage.getMainWindowSync().on('avoidAreaChange', (data) => {
      if (data.type == window.AvoidAreaType.TYPE_SYSTEM) {
        WindowUtil.setStatusBarHeight = data.area.topRect.height
      } else if (data.type == window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR) {
        WindowUtil.setNavigationBarHeight = data.area.bottomRect.height
      }
    })
    windowStage.loadContent('pages/HMRouterIndex', (err) => {
      if (err.code) {
        Logger.info('Failed to load the content. Cause: '+JSON.stringify(err), this);
        return;
      }
      windowStage.getMainWindow().then((windowObj) => {
        // getUIContext接口需要再loadContent调用后调用，否则获取的UIContext可能为空
        DialogHub.init(windowObj.getUIContext());
      })
    });
  }

  onConfigurationUpdate(newConfig: Configuration): void {
    AppManager.preference.color_mode = newConfig.colorMode!
  }

  onWindowStageDestroy(): void {
    WindowUtil.windowStageDestroy()
  }

  onForeground(): void {
    WindowUtil.foreground()
  }

  onBackground(): void {
    WindowUtil.background()
  }
}