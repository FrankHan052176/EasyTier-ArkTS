import { Configuration, UIAbility, Want, WantAgent, wantAgent } from "@kit.AbilityKit";
import { backgroundTaskManager } from "@kit.BackgroundTasksKit";
import { geoLocationManager } from "@kit.LocationKit";
import { window } from "@kit.ArkUI";
import { EventHelper } from "../util/EventHelper";
import { Logger, LogLocate } from "../util/Logger";
import { BusinessError } from "@kit.BasicServicesKit";
import easytier from "easytier-ohrs"
import { vpnExtension } from "@kit.NetworkKit";
import { PermissionUtil } from "../PermissionUtil";
import Manager from "../Manager";
import { objectToHomoTOML } from "../util/Conversion";
import { readConfig } from "../util/Compress";
import { url } from "@kit.ArkTS";
import entry from 'libentry.so'
import { BUILD_TIME } from "../util/info/BuildTime";
import { SpiderMan } from "@simplepeng/spider-man";
import { WindowUtil } from "../WindowUtil";
import { HMRouterMgr } from "@hadss/hmrouter";
import { AppManager } from "../AppManager";
import { HMRouterTransitions } from "@hadss/hmrouter-transitions";

@LogLocate("EntryAbility")
export default class EntryAbility extends UIAbility {
  vpnConnection: vpnExtension.VpnConnection | undefined

  startContinuousTask(inst_id: string) {
    if (!canIUse("SystemCapability.ResourceSchedule.BackgroundTaskManager.ContinuousTask")) return;
    let config = Manager.configs.get(inst_id)
    if (!config) return
    if (!AppManager.permission.isGetLocPerm()) {
      easytier.runNetworkInstance(objectToHomoTOML(config!))
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
            if (easytier.runNetworkInstance(objectToHomoTOML(config!))) {
              geoLocationManager.on('locationChange', request, () => {
                Logger.debug("GeoLoc alive", this)
              });
            }else {
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
        this.startContinuousTask(data.data!.inst_id);
      })
    })
  }

  stop_bg_Listener() {
    Logger.debug("stop_bg_Listener", this)
    EventHelper.emitterListener("stop_bg",(data) => {
      Logger.info("stop_bg_task", this)
      this.stopContinuousTask()
      easytier.stopNetworkInstance([data.data!.inst_id])
    })
  }

  setup_tun_Listener() {
    Logger.debug("setup_tun_Listener", this)
    EventHelper.emitterListener("setup_tun", (data) => {
      Logger.info("setup_tun", this)
      let ip = data.data!.ip as string
      let mask = data.data!.mask as number
      let vpnConfig: vpnExtension.VpnConfig = {
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
        dnsAddresses: data.data!.magicDNS?["100.100.100.101"]:undefined
      }
      if (this.vpnConnection === undefined) {
        Logger.error("vpnConnection not found", this)
      }
      this.vpnConnection!.create(vpnConfig).then((fd) => {
        easytier.setTunFd(data.data!.id as string, fd)
      })
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