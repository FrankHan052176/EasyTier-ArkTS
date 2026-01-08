import { Configuration, UIAbility, Want, WantAgent, wantAgent } from '@kit.AbilityKit';
import { backgroundTaskManager } from '@kit.BackgroundTasksKit';
import { geoLocationManager } from '@kit.LocationKit';
import { window } from '@kit.ArkUI';
import { EventHelper } from '../util/EventHelper';
import { Logger, LogLocate } from '../util/Logger';
import { BusinessError, deviceInfo, emitter } from '@kit.BasicServicesKit';
import easytier from 'easytier-ohrs';
import { vpnExtension } from '@kit.NetworkKit';
import { stringArr2RouteArr } from '../util/Conversion';
import { JSON, url } from '@kit.ArkTS';
import entry from 'libentry.so';
import { BUILD_TIME } from '../util/info/BuildTime';
import { SpiderMan } from '@simplepeng/spider-man';
import { WindowUtil } from '../WindowUtil';
import { HMRouterMgr } from '@hadss/hmrouter';
import { AppManager } from '../AppManager';
import { HMRouterTransitions } from '@hadss/hmrouter-transitions';
import { DialogHub } from '@hadss/dialoghub';
import { sendToast } from '../ToastUtil';
import { isIpAddr } from '../class/config/IP';
import { distributedKVStore } from '@kit.ArkData';
import { BottomAnimator } from '../class/animator/BottomAnimator';
import { ContentUtil } from '../ContentUtil';
import { fileUri, fileIo as fs } from '@kit.CoreFileKit';
import { systemShare } from '@kit.ShareKit';
import { rpc } from '@kit.IPCKit';
import { unwrapUrl } from '../util/ShareUtil';
import { updateFavorite } from '../CommunicationUtil';

@LogLocate("EntryAbility")
export default class EntryAbility extends UIAbility {
  vpnConnection: vpnExtension.VpnConnection | undefined

  startContinuousTask(cfg: string, uuid: string | undefined) {
    if (!AppManager.permission.isGetLocPerm() ||
      !canIUse("SystemCapability.ResourceSchedule.BackgroundTaskManager.ContinuousTask")) {
      if (!easytier.runNetworkInstance(cfg)) {
        sendToast("实例启动失败, 可能是内核错误, 请上报日志.", $r("sys.symbol.exclamationmark_circle"), 1)
        Logger.error("启动失败", this)
      }
      return
    }
    Logger.info("start background alive", this)
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
          backgroundTaskManager.startBackgroundRunning(this.context, ["location", "dataTransfer"], wantAgentObj).then(() => {
            if (easytier.runNetworkInstance(cfg)) {
              setTimeout(() => {
                updateFavorite()
              }, 300)
              if (uuid) {
                HMRouterMgr.to('StatusPage')
                  .withParam(uuid)
                  .withAnimator(new BottomAnimator())
                  .pushAsync()
              }
              geoLocationManager.on('locationChange', request, () => {
                Logger.debug("GeoLoc alive", this)
              });
            } else {
              sendToast("实例启动失败, 可能是内核错误, 请上报日志.", $r("sys.symbol.exclamationmark_circle"), 1)
              Logger.error("启动失败", this)
              this.stopContinuousTask()
            }
          }).catch(() => {
          });
        } catch (error) {
        }
      }).catch(() => {
      });
    } catch (error) {
    }
  }

  stopContinuousTask() {
    if (!canIUse("SystemCapability.ResourceSchedule.BackgroundTaskManager.ContinuousTask")) {
      return;
    }
    Logger.info("stop background alive", this)
    try {
      geoLocationManager.off("locationChange")
    } catch (error) {
    }
    backgroundTaskManager.stopBackgroundRunning(this.context).then(() => {
      this.vpnConnection?.destroy().catch(() => {
      })
    }).catch(() => {
    });
  }

  onCreate(want: Want) {
    this.listenCardCall()
    HMRouterMgr.openLog("INFO")
    HMRouterMgr.init({
      context: this.context
    })
    if (deviceInfo.productModel !== "emulator") {
      entry.hilogInit()
      easytier.hilogGlobalOptions(0, "fhl")
      easytier.initPanicHook()
    }
    Logger.info("BuildTime:" + BUILD_TIME, this)
    this.start_bg_Listener()
    this.stop_bg_Listener()
    this.setup_tun_Listener()
    WindowUtil.colorMode = this.context.config.colorMode ?? -1
    this.initApp()
    this.readSharedData(want)
    this.context.getApplicationContext().eventHub.on("test", () => {
      Logger.error("test", this)
    })
  }

  async initApp() {
    AppManager.uiState.init()
    ContentUtil.initConfigFields()
    if (deviceInfo.productModel !== "emulator") {
      AppManager.easytier.init()
    }
    try {
      AppManager.preference.init(this.context)
    } catch (error) {
      Logger.error(`PreferenceUtil failed to init.\n${error}`, AppManager)
    }
    AppManager.data.init()
  }

  onNewWant(want: Want) {
    Logger.debug("onNetWant", this)
    this.readSharedData(want)
    updateFavorite()
  }

  listenCardCall() {
    this.callee.on("send_card_id", (indata: rpc.MessageSequence) => {
      const obj = JSON.parse(indata.readString()) as object
      const formId = obj['formId'] as string
      AppManager.preference.addCardId(formId)
      return null
    })
    this.callee.on("start_favorite", () => {
      if (AppManager.uiState.favorite) {
        if (AppManager.easytier.isFavoritesRunning()) {
          AppManager.easytier.stop()
        } else {
          if (AppManager.easytier.runningNetworks.size > 0) {
            AppManager.easytier.stop()
          }
          AppManager.easytier.start(AppManager.uiState.favorite, true)
        }
      }
      return null
    })
  }

  async readSharedData(want: Want) {
    let uri = want.uri;
    if (uri && uri.length > 0) {
      Logger.info("get uri:" + uri, this)
      try {
        let urlObject = url.URL.parseURL(uri);
        unwrapUrl(urlObject)
      } catch (err) {
        let error = err as BusinessError;
        Logger.error(`readSharedData error, code: ${error.code}, mesage: ${error.message}`, this);
      }
    } else {
      systemShare.getSharedData(want)
        .then((data: systemShare.SharedData) => {
          data?.getRecords()?.forEach(async (record: systemShare.SharedRecord) => {
            if (record.uri && record.uri.length > 0) {
              Logger.debug("read shared file: " + JSON.stringify(record), this)
              try {
                let cfg = fs.readTextSync(new fileUri.FileUri(record.uri).path)
                AppManager.data.importToml(cfg)
              } catch (error) {
                Logger.debug("read file error: " + JSON.stringify(error), this)
              }
            } else if (record.content && record.content.length > 0) {
              let urlObject = url.URL.parseURL(record.content);
              let hostname = urlObject.hostname
              switch (hostname) {
                case "appgallery.huawei.com": {
                  let app = urlObject.params.get("id")
                  Logger.debug("get AppId: " + app, this)
                  AppManager.web.getAppInfo(app!, (name, icon) => {
                    AppManager.preference.setAppInfo(app!, name, icon)
                  })
                  break;
                }
                case "easytier.cn": {
                  unwrapUrl(urlObject)
                  break;
                }
              }
            }
          })
        })
    }
  }

  onDestroy() {
    Logger.debug("onDestroy", this)
    this.stopContinuousTask()
    this.callee.off("send_card_id")
    this.callee.off("start_favorite")
  }

  start_bg_Listener() {
    Logger.debug("start_bg_Listener", this)
    EventHelper.emitterListener("start_bg", (data) => {
      this.prepare_vpn(() => {
        Logger.info("start_bg_task", this)
        this.startContinuousTask(data.data!.cfg, data.data?.uuid);
      })
    })
  }

  stop_bg_Listener() {
    Logger.debug("stop_bg_Listener", this)
    EventHelper.emitterListener("stop_bg", () => {
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
    } else {
      return "223.5.5.5"
    }
  }

  setup_tun(ip: string, mask: number, magicDNS: boolean, inst_id: string, needExitNode: boolean) {
    Logger.debug("当前IP:" + ip, this)
    Logger.debug("当前路由表:" + Array.from(AppManager.easytier.tunRoutes).join(","), this)
    let vpnConfig: vpnExtension.VpnConfig = AppManager.preference.vpn_routes || deviceInfo.sdkApiVersion >= 20 ? {
      addresses: [
        {
          address: {
            address: ip,
            family: 1,
          },
          prefixLength: mask
        }
      ],
      blockedApplications: [
        "top.frankhan.easytier",
        ...AppManager.preference.getBlackList()
      ],
      trustedApplications: [],
      dnsAddresses: magicDNS ? ["100.100.100.101"] : (AppManager.preference.dev ? [this.safeDns()] : ["223.5.5.5"]),
      mtu: 1380,
      routes: stringArr2RouteArr(ip, magicDNS, needExitNode)
    } : {
      addresses: [
        {
          address: {
            address: ip,
            family: 1,
          },
          prefixLength: mask
        }
      ],
      blockedApplications: [
        "top.frankhan.easytier",
        ...AppManager.preference.getBlackList()
      ],
      trustedApplications: [],
      dnsAddresses: magicDNS ? ["100.100.100.101"] : (AppManager.preference.dev ? [this.safeDns()] : ["223.5.5.5"]),
      mtu: 1380
    }
    if (this.vpnConnection === undefined) {
      Logger.error("vpnConnection not found", this)
    }
    Logger.debug("VPN配置:" + JSON.stringify(vpnConfig), this)
    this.vpnConnection!.create(vpnConfig).then((fd) => {
      easytier.setTunFd(inst_id, fd)
    }).catch(() => {
    })
  }

  prepare_vpn(callback: () => void = () => {
  }) {
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
    let context = this.context;
    try {
      const kvManagerConfig: distributedKVStore.KVManagerConfig = {
        bundleName: 'top.frankhan.easytier',
        context: context,
      }
      AppManager.KVManager = distributedKVStore.createKVManager(kvManagerConfig)
    } catch (e) {
      let error = e as BusinessError;
      Logger.info(`Failed to create KVManager. Code:${error.code},message:${error.message}`, this);
    }
    try {
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
    } catch (error) {
    }
    windowStage.loadContent('pages/HMRouterIndex', (err) => {
      if (err.code) {
        Logger.error('Failed to load the content. Cause: ' + JSON.stringify(err), this);
        return;
      }
      windowStage.getMainWindow().then((windowObj) => {
        try {
          DialogHub.init(windowObj.getUIContext());
        } catch (error) {
        }
      }).catch(() => {
      })
    });
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

  onConfigurationUpdate(newConfig: Configuration): void {
    WindowUtil.colorMode = newConfig.colorMode ?? -1
    EventHelper.emitterPublish("update_color_mode")
  }
}