import { ConfigurationConstant, UIAbility, WantAgent, wantAgent } from "@kit.AbilityKit";
import { backgroundTaskManager } from "@kit.BackgroundTasksKit";
import { geoLocationManager } from "@kit.LocationKit";
import { display, window } from "@kit.ArkUI";
import EventHelper from "../util/EventHelper";
import Logger from "../util/Logger";
import { BusinessError, deviceInfo } from "@kit.BasicServicesKit";
import { distributedKVStore } from "@kit.ArkData";
import easytier from "libeasytier_ohrs.so"
import { vpnExtension } from "@kit.NetworkKit";
import { requestVpnPerm } from "../util/Permission";
import { VpnConfig } from "../util/config/VpnConfig";

export default class EntryAbility extends UIAbility {
  vpnConnection: vpnExtension.VpnConnection | undefined
  tun_fd: number = -1
  inst_names: Set<string> = new Set

  startContinuousTask(inst_id: string) {
    if (!canIUse("SystemCapability.ResourceSchedule.BackgroundTaskManager.ContinuousTask")) return;
    Logger.info("[EntryAbi] start background alive")
    let wantAgentInfo: wantAgent.WantAgentInfo = {
      wants: [
        {
          bundleName: "top.frankhan.et4hm",
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
            // TODO：启动后端否则this.stopContinuousTask()
          }).catch(() => {});
        } catch (error) {}
      });
    } catch (error) {}
  }

  stopContinuousTask() {
    this.vpnConnection!.destroy()
    if (!canIUse("SystemCapability.ResourceSchedule.BackgroundTaskManager.ContinuousTask")) return;
    Logger.info("[EntryAbi] stop background alive")
    backgroundTaskManager.stopBackgroundRunning(this.context).then(() => {
    }).catch(() => {});
  }

  async refreshColorMode(colorMode: ConfigurationConstant.ColorMode) {
    this.context.getApplicationContext().setColorMode(colorMode);
  }

  async onCreate() {
    Logger.debug("[EntryAbi] onCreate")
    // easytier.initPanicHook()
    // easytier.hilogGlobalOptions(0, "fhl")
    // easytier.initTracingSubscriber()
    this.start_bg_Listener()
    this.stop_bg_Listener()
    this.color_mode_Listener()
    this.setup_tun_Listener()
  }

  onDestroy() {
    Logger.debug("[EntryAbi] onDestroy")
    this.stopContinuousTask()
    this.vpnConnection!.destroy()
  }

  start_bg_Listener() {
    Logger.debug("[EntryAbi] start_bg_Listener")
    EventHelper.emitterListener("start_bg",(data) => {
      this.prepare_vpn(() => {
        Logger.debug("[EntryAbi] start_bg_task")
        this.startContinuousTask(data.data!.inst_id);
      })
    })
  }

  stop_bg_Listener() {
    Logger.debug("[EntryAbi] stop_bg_Listener")
    EventHelper.emitterListener("stop_bg",() => {
      this.stopContinuousTask()
    })
  }

  color_mode_Listener() {
    Logger.debug("[EntryAbi] color_mode_Listener")
    EventHelper.emitterListener("color_mode", (data) => {
      let darkMode = data.data!.colorMode as number
      Logger.debug("color_mode 更新"+darkMode)
      this.refreshColorMode(darkMode)
    })
  }

  setup_tun_Listener() {
    Logger.debug("[EntryAbi] setup_tun_Listener")
    EventHelper.emitterListener("setup_tun", (data) => {
      Logger.debug("setup_tun")
      let ip = data.data!.ip as string
      let mask = data.data!.mask as number
      let cfg = new VpnConfig(ip, mask, ["223.5.5.5"])
      if (this.vpnConnection === undefined) {
        Logger.debug("vpnConnection not found")
      }
      this.vpnConnection!.create(cfg).then((fd) => {
        //TODO: 调用easytier.setTunFd
      })
    })
  }

  prepare_vpn(callback: () => void = () => {}) {
    if (deviceInfo.productModel === "emulator") return;
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
    display.getDefaultDisplaySync().getCutoutInfo((err: BusinessError, data: display.CutoutInfo) => {
      const errCode: number = err.code;
      if (errCode) {
        console.error(`Failed to get cutoutInfo. Code: ${err.code}, message: ${err.message}`);
        return;
      }
      let maxHeight = 0
      data.boundingRects.forEach((value) => {
        maxHeight = Math.max(maxHeight, px2vp(Math.min(value.top+value.height, value.left+value.width)))
      })
      AppStorage.setOrCreate("cutHeight", maxHeight)
    });
    windowStage.getMainWindow().then((windowClass) => {
      windowClass.setWindowSystemBarEnable(['status']);
      AppStorage.setOrCreate('winWidth', px2vp(windowClass.getWindowProperties().windowRect.width));
      AppStorage.setOrCreate('winHeight', px2vp(windowClass.getWindowProperties().windowRect.height));
      windowClass.on('windowSizeChange', (windowSize) => {
        EventHelper.emitterPublish("windowSizeChange", {
          data:{
            width: px2vp(windowSize.width),
            height: px2vp(windowSize.height)
          }
        })
      });
    })
    // 启动数据库
    let kvManager: distributedKVStore.KVManager | undefined = undefined;
    let context = this.context;
    try {
      const kvManagerConfig: distributedKVStore.KVManagerConfig = {
        bundleName: 'top.frankhan.et4hm',
        context: context,
      }
      kvManager = distributedKVStore.createKVManager(kvManagerConfig);
      Logger.debug('Succeeded in creating KVManager.');
      // 通过kvManager读取数据
    } catch (e) {
      let error = e as BusinessError;
      Logger.debug(`Failed to create KVManager. Code:${error.code},message:${error.message}`);
    }
    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        Logger.debug('Failed to load the content. Cause: '+JSON.stringify(err));
        return;
      }
      this.prepare_vpn()
    });
  }

  onWindowStageDestroy(): void {
  }

  onForeground(): void {
    Logger.info("Foreground")
    // TODO 设置前台启动更新
  }

  onBackground(): void {
    Logger.info("Background")
    // TODO 设置后台停止更新
  }
}