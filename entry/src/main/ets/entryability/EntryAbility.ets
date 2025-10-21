import { ConfigurationConstant, UIAbility, Want, WantAgent, wantAgent } from "@kit.AbilityKit";
import { backgroundTaskManager } from "@kit.BackgroundTasksKit";
import { geoLocationManager } from "@kit.LocationKit";
import { window } from "@kit.ArkUI";
import EventHelper from "../util/EventHelper";
import Logger from "../util/Logger";
import { BusinessError } from "@kit.BasicServicesKit";
import { distributedKVStore, preferences } from "@kit.ArkData";
import easytier from "libeasytier_ohrs.so"
import { vpnExtension } from "@kit.NetworkKit";
import { isGetLocPerm, requestVpnPerm } from "../util/Permission";
import Manager, { UIType } from "../Manager";
import { objectToHomoTOML } from "../util/Conversion";
import { readConfig } from "../util/Compress";
import { url } from "@kit.ArkTS";
import entry from 'libentry.so'
import { BUILD_TIME } from "../util/info/BuildTime";
import { SpiderMan } from "@simplepeng/spider-man";

export default class EntryAbility extends UIAbility {
  vpnConnection: vpnExtension.VpnConnection | undefined

  startContinuousTask(inst_id: string) {
    if (!canIUse("SystemCapability.ResourceSchedule.BackgroundTaskManager.ContinuousTask")) return;
    let config = Manager.configs.get(inst_id)
    if (!config) return
    if (!isGetLocPerm()) {
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
                Logger.debug("[EntryAbi] GeoLoc alive")
              });
            }else {
              Logger.error("[EntryAbi] 启动失败")
              this.stopContinuousTask()
            }
          }).catch(() => {});
        } catch (error) {}
      });
    } catch (error) {}
  }

  stopContinuousTask() {
    if (!canIUse("SystemCapability.ResourceSchedule.BackgroundTaskManager.ContinuousTask")) return;
    Logger.info("[EntryAbi] stop background alive")
    geoLocationManager.off("locationChange")
    backgroundTaskManager.stopBackgroundRunning(this.context).then(() => {
      this.vpnConnection?.destroy()
    }).catch(() => {});
  }

  async refreshColorMode(colorMode: ConfigurationConstant.ColorMode) {
    this.context.getApplicationContext().setColorMode(colorMode);
  }

  onCreate(want: Want) {
    entry.hilogInit()
    Logger.debug("[EntryAbi] onCreate")
    Logger.info("[EntryAbi] BuildVersion:"+BUILD_TIME)
    easytier.initPanicHook()
    this.start_bg_Listener()
    this.stop_bg_Listener()
    this.color_mode_Listener()
    this.setup_tun_Listener()
    this.readSharedData(want)
  }

  onNewWant(want: Want) {
    Logger.debug("[EntryAbi] onNetWant")
    this.readSharedData(want)
  }

  readSharedData(want: Want) {
    let uri = want.uri;
    if (uri) {
      Logger.info("[EntryAbi] get uri:"+uri)
      try {
        let urlObject = url.URL.parseURL(uri);
        let cfg = urlObject.params.get("cfg")
        if (cfg) {
          readConfig(cfg)
        }
      } catch (err) {
        let error = err as BusinessError;
        Logger.error(`onAddForm err, code: ${error.code}, mesage: ${error.message}`);
      }
    }
  }

  onDestroy() {
    Logger.debug("[EntryAbi] onDestroy")
    this.stopContinuousTask()
  }

  start_bg_Listener() {
    Logger.debug("[EntryAbi] start_bg_Listener")
    EventHelper.emitterListener("start_bg",(data) => {
      this.prepare_vpn(() => {
        Logger.info("[EntryAbi] start_bg_task")
        this.startContinuousTask(data.data!.inst_id);
      })
    })
  }

  stop_bg_Listener() {
    Logger.debug("[EntryAbi] stop_bg_Listener")
    EventHelper.emitterListener("stop_bg",(data) => {
      Logger.info("[EntryAbi] stop_bg_task")
      this.stopContinuousTask()
      easytier.stopNetworkInstance([data.data!.inst_id])
    })
  }

  color_mode_Listener() {
    Logger.debug("[EntryAbi] color_mode_Listener")
    EventHelper.emitterListener("color_mode", (data) => {
      let darkMode = data.data!.colorMode as number
      Logger.info("[EntryAbi] color_mode 更新"+darkMode)
      this.refreshColorMode(darkMode)
    })
  }

  setup_tun_Listener() {
    Logger.debug("[EntryAbi] setup_tun_Listener")
    EventHelper.emitterListener("setup_tun", (data) => {
      Logger.info("[EntryAbi] setup_tun")
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
        Logger.error("[EntryAbi] vpnConnection not found")
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
    Logger.info("[EntryAbi] prepare vpn")
    requestVpnPerm(() => {
      this.vpnConnection = vpnExtension.createVpnConnection(getContext(this) as vpnExtension.VpnExtensionContext)
      callback()
    })
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    SpiderMan.init();
    let kvManager: distributedKVStore.KVManager | undefined = undefined;
    let context = this.context;
    try {
      const kvManagerConfig: distributedKVStore.KVManagerConfig = {
        bundleName: 'top.frankhan.easytier',
        context: context,
      }
      kvManager = distributedKVStore.createKVManager(kvManagerConfig);
      Manager.KVManager = kvManager
    } catch (e) {
      let error = e as BusinessError;
      Logger.info(`[EntryAbi] Failed to create KVManager. Code:${error.code},message:${error.message}`);
    }
    Manager.Preferences = preferences.getPreferencesSync(this.context, { name: 'EasyTierPreferences' });
    if (Manager.Preferences.getSync("show_log", false)) {
      easytier.hilogGlobalOptions(0, "fhl")
      easytier.initTracingSubscriber()
      Manager.show_log = true
    }
    windowStage.getMainWindowSync().on('windowSizeChange', (data) => {
      if (Manager.uiContext) {
        Manager.width = Manager.uiContext.px2vp(data.width)
        Manager.height = Manager.uiContext.px2vp(data.height)
      }else {
        Manager.width = px2vp(data.width)
        Manager.height = px2vp(data.height)
      }
      if (Manager.width < 720) {
        Manager.uiType = UIType.Column_1
      }else if (Manager.width >= 1080) {
        Manager.uiType = UIType.Column_3
      }else {
        Manager.uiType = UIType.Column_2
      }
    });
    windowStage.getMainWindowSync().on('avoidAreaChange', (data) => {
      if (data.type == window.AvoidAreaType.TYPE_SYSTEM) {
        let topRectHeight = data.area.topRect.height;
        Manager.statusBarHeight = Manager.uiContext?Manager.uiContext.px2vp(topRectHeight):px2vp(topRectHeight)
      } else if (data.type == window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR) {
        let bottomRectHeight = data.area.bottomRect.height;
        Manager.navigationBarHeight = Manager.uiContext?Manager.uiContext.px2vp(bottomRectHeight):px2vp(bottomRectHeight)
      }
    })
    windowStage.loadContent('pages/NavIndex', (err) => {
      if (err.code) {
        Logger.info('[EntryAbi] Failed to load the content. Cause: '+JSON.stringify(err));
        return;
      }
    });
  }

  onWindowStageDestroy(): void {
  }

  onForeground(): void {
    Logger.info("[EntryAbi] Foreground")
    // TODO 设置前台启动更新
  }

  onBackground(): void {
    Logger.info("[EntryAbi] Background")
    // TODO 设置后台停止更新
  }
}