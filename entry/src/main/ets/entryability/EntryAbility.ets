import { AbilityConstant, Configuration, UIAbility, Want, WantAgent, wantAgent } from '@kit.AbilityKit';
import { backgroundTaskManager } from '@kit.BackgroundTasksKit';
import { geoLocationManager } from '@kit.LocationKit';
import { window } from '@kit.ArkUI';
import { EventHelper } from '../util/EventHelper';
import { Logger, LogLocate } from '../util/Logger';
import { BusinessError, deviceInfo, emitter } from '@kit.BasicServicesKit';
import easytier from 'easytier-ohrs';
import easytier_release from 'easytier-release';
import { vpnExtension } from '@kit.NetworkKit';
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
import { cancelNotification, publishTextNotification } from '../util/NoticeHelper';
import { netHandover } from '@kit.NetworkBoostKit';
import { cleanEmpty } from '../MappedUtil';
import { NetworkConfig } from '../protobuf/api_manage';

@LogLocate("EntryAbility")
export default class EntryAbility extends UIAbility {
  vpnConnection: vpnExtension.VpnConnection | undefined

  startContinuousTask(cfg: string, uuid: string | undefined, name: string | undefined) {
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
    let request: geoLocationManager.LocationRequest = {
      priority: geoLocationManager.LocationRequestPriority.LOW_POWER,
      timeInterval: 7200,
      distanceInterval: 10000,
      maxAccuracy: 1000
    };
    try {
      wantAgent.getWantAgent(wantAgentInfo).then((wantAgentObj: WantAgent) => {
        try {
          backgroundTaskManager.startBackgroundRunning(this.context, ["location"], wantAgentObj).then(() => {
            if (AppManager.preference.inittedGitCore?easytier.runNetworkInstance(cfg):easytier_release.runNetworkInstance(cfg)) {
              setTimeout(() => {
                updateFavorite()
                publishTextNotification(name ?? "N/A")
              }, 300)
              if (uuid) {
                HMRouterMgr.to('StatusPage')
                  .withParam(uuid)
                  .withAnimator(new BottomAnimator())
                  .pushAsync()
              }
              geoLocationManager.on('locationChange', request, () => {});
            } else {
              sendToast("实例启动失败, 可能是内核错误, 请上报日志.", $r("sys.symbol.exclamationmark_circle"), 1)
              Logger.error("启动失败", this)
              this.stopContinuousTask()
            }
          }).catch((err: BusinessError) => {
            Logger.error(`startBackgroundRunning failed: ${err.code}, ${err.message}`, this)
          });
        } catch (error) {
          Logger.error(`startBackgroundRunning error: ${JSON.stringify(error)}`, this)
        }
      }).catch((err: BusinessError) => {
        Logger.error(`getWantAgent failed: ${err.code}, ${err.message}`, this)
      });
    } catch (error) {
      Logger.error(`getWantAgent error: ${JSON.stringify(error)}`, this)
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
      Logger.error(`off locationChange error: ${JSON.stringify(error)}`, this)
    }
    const destroyVpn = () => {
      if (this.vpnConnection) {
        this.vpnConnection.destroy().then(() => {
          Logger.info("vpnConnection destroyed", this)
          this.vpnConnection = undefined
        }).catch((err: BusinessError) => {
          Logger.error(`vpnConnection destroy failed: ${err.code}, ${err.message}`, this)
        })
      }
    }
    backgroundTaskManager.stopBackgroundRunning(this.context).catch((err: BusinessError) => {
      Logger.error(`stopBackgroundRunning failed: ${err.code}, ${err.message}`, this)
    }).finally(() => {
      destroyVpn()
      cancelNotification()
    });
  }

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam) {
    this.listenCardCall()
    HMRouterMgr.openLog("INFO")
    HMRouterMgr.init({
      context: this.context
    })
    Logger.info("BuildTime:" + BUILD_TIME, this)
    this.start_bg_Listener()
    this.stop_bg_Listener()
    this.setup_tun_Listener()
    WindowUtil.colorMode = this.context.config.colorMode ?? -1
    this.initApp().then(() => {
      this.readSharedData(want)
      if (launchParam.launchReason === AbilityConstant.LaunchReason.CONTINUATION) {
        if (want.parameters !== undefined) {
          let url = want.parameters.data
          // TODO: 不保存启动
        }
      }
      if (deviceInfo.productModel !== "emulator") {
        entry.hilogInit()
        easytier.hilogGlobalOptions(0, "fhl")
        easytier_release.hilogGlobalOptions(0, "fhl")
      }
      if (AppManager.preference.inittedGitCore) {
        easytier.initPanicHook()
      }else {
        easytier_release.initPanicHook()
      }
    })
  }

  async initApp() {
    AppManager.uiState.init()
    ContentUtil.initConfigFields()
    try {
      await AppManager.preference.init(this.context)
    } catch (error) {
      Logger.error(`PreferenceUtil failed to init.\n${error}`, AppManager)
    }
    if (!AppManager.preference.noOldData) {
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
    }
    await AppManager.data.init()
    if (deviceInfo.productModel !== "emulator") {
      AppManager.easytier.init()
    }
    netHandover.on('handoverChange', (info: netHandover.HandoverInfo) => {
      if (info.handoverStart) {

      }else if (info.handoverComplete) {

      }
    })
  }

  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam) {
    Logger.debug("onNetWant", this)
    this.readSharedData(want)
    updateFavorite()
    if (launchParam.launchReason === AbilityConstant.LaunchReason.CONTINUATION) {
      if (want.parameters !== undefined) {
        let url = want.parameters.data
        // TODO: 不保存启动
      }
    }
  }

  listenCardCall() {
    this.callee.on("send_card_id", (indata: rpc.MessageSequence) => {
      try {
        const obj = JSON.parse(indata.readString()) as object
        const formId = obj['formId'] as string
        AppManager.preference.addCardId(formId)
      } catch (error) {
        Logger.error(`send_card_id parse error: ${JSON.stringify(error)}`, this)
      }
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
                let cfg = ""
                try {
                  cfg = fs.readTextSync(new fileUri.FileUri(record.uri).path)
                } catch (e) {
                   Logger.error("fs read error: " + JSON.stringify(e), this)
                }
                if (cfg) {
                  AppManager.data.importToml(cfg)
                }
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

  onContinue(wantParam: Record<string, Object>): AbilityConstant.OnContinueResult {
    if (AppManager.easytier.runningNetworks.size > 0) {
      let uuid = AppManager.easytier.runningNetworks.keys().next().value as string
      let cfg = AppManager.data.configUUIDMap.get(uuid)
      if (cfg) {
        wantParam['data'] = JSON.stringify(cleanEmpty(cfg))
      }else {
        return AbilityConstant.OnContinueResult.MISMATCH;
      }
      return AbilityConstant.OnContinueResult.AGREE;
    }else {
      return AbilityConstant.OnContinueResult.MISMATCH;
    }
  }

  start_bg_Listener() {
    Logger.debug("start_bg_Listener", this)
    EventHelper.emitterListener("start_bg", (data) => {
      this.prepare_vpn(() => {
        Logger.info("start_bg_task", this)
        this.startContinuousTask(data.data!.cfg, data.data?.uuid, data.data?.name);
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
    let appList = [
      deviceInfo.sdkApiVersion >= 22? "":"top.frankhan.easytier",
      ...AppManager.preference.getBlackList()
    ]
    let vpnConfig: vpnExtension.VpnConfig = {
      addresses: [
        {
          address: {
            address: ip,
            family: 1,
          },
          prefixLength: mask
        }
      ],
      blockedApplications: AppManager.preference.white_list?[]:appList,
      trustedApplications: AppManager.preference.white_list?appList:[],
      dnsAddresses: magicDNS ? ["100.100.100.101"] : (AppManager.preference.dev ? [this.safeDns()] : ["223.5.5.5"]),
      mtu: 1380,
      routes: AppManager.preference.getVpnCfgRoutes(ip, magicDNS, needExitNode)
    }
    if (this.vpnConnection === undefined) {
      Logger.error("vpnConnection not found", this)
      return
    }
    Logger.debug("VPN配置:" + JSON.stringify(vpnConfig), this)
    this.vpnConnection.create(vpnConfig).then((fd) => {
      if (AppManager.preference.inittedGitCore) {
        easytier.setTunFd(inst_id, fd)
      }else {
        easytier_release.setTunFd(inst_id, fd)
      }
    }).catch((error: BusinessError) => {
      Logger.error(`vpnConnection create failed: ${error.code}, ${error.message}`, this)
    })
  }

  prepare_vpn(callback: () => void = () => {}) {
    if (this.vpnConnection !== undefined) {
      callback()
      return;
    }
    Logger.info("prepare vpn", this)
    AppManager.permission.requestVpnPerm(async () => {
      this.vpnConnection = vpnExtension.createVpnConnection(getContext(this) as vpnExtension.VpnExtensionContext)
      if (deviceInfo.sdkApiVersion >= 22) {
        await this.vpnConnection.protectProcessNet()
      }
      callback()
    })
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    SpiderMan.init();
    HMRouterTransitions.init(windowStage);
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