import Manager from '../Manager'
import { Config } from '../util/config/ETConfig'
import {
  AddSheet,
  AddSheetTitle,
  settingSheet,
  SharedPeersSheet,
  SharedPeersTitle, ToolButton } from './Components'
import { InstanceCard } from './InstanceCard'
import { InstanceContent } from './InstanceContent'
import easytier, { KeyValuePair } from "libeasytier_ohrs.so"
import { requestDistributePerm, updatePermStatus } from '../util/Permission'
import { objectToHomoTOML, tomlToConfig, unwrappedEvents } from '../util/Conversion'
import EventHelper from '../util/EventHelper'
import { JSON } from '@kit.ArkTS'
import { NetworkInstanceRunningInfo } from '../util/info/PeerInfo'
import entry from 'libentry.so'
import { InstanceStatus } from './InstanceStatus'
import { systemShare } from '@kit.ShareKit';
import { uniformTypeDescriptor as utd } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { BusinessError, pasteboard } from '@kit.BasicServicesKit';
import Logger from '../util/Logger'
import { compressedConfig, readConfig } from '../util/Compress'
import { deferredLink } from '@kit.AppLinkingKit'

@Entry
@ComponentV2
struct Index {
  @Local realIndex: number = 0
  @Local controller: SwiperController = new SwiperController()
  @Local showSideBar: boolean = false
  @Local addSheet: boolean = false
  @Local importSheet: boolean = false
  @Local shareMenu: boolean = false
  @Local sharedPeersSheet: boolean = false
  @Local setting: boolean = false
  @Local addSheet_name: string = ""
  // // API20
  // private immersiveCallback = async (sharableTarget: harmonyShare.SharableTarget) => {
  //   let shareData: systemShare.SharedData = new systemShare.SharedData({
  //     utd: utd.UniformDataType.HYPERLINK,
  //     content: 'https://easytier.cn/share_cfg_'+(await compressedConfig(Manager.getConfigs()[this.realIndex])),
  //     title: '分享配置 '+Manager.getConfigs()[this.realIndex].instance_name,
  //     description: Manager.getConfigs()[this.realIndex].instance_id
  //   });
  //   sharableTarget.share(shareData);
  // }
  //
  // onPageShow(): void {
  //   harmonyShare.on('gesturesShare', this.immersiveCallback);
  // }
  //
  // onPageHide(): void {
  //   harmonyShare.off('gesturesShare', this.immersiveCallback);
  // }

  aboutToAppear(): void {
    entry.hilogInit()
    updatePermStatus()
    Manager.readDB(Manager.KVManager!)
    Manager.updateQQGroups()
    Manager.updateSharedPeers()
    setInterval(() => {
      Manager.updateQQGroups()
      Manager.updateSharedPeers()
    }, 1800000)
    Manager.preference_log = Manager.Preferences!.getSync("show_log", false).valueOf() as boolean
    Manager.Preferences!.on("dataChange", ["show_log"], (value) => {
      for (const keyValue of Object.entries(value)) {
        Manager.preference_log = (keyValue[1]).valueOf() as boolean
      }
    })
    EventHelper.emitterListener("windowSizeChange", (data) => {
      Manager.width = this.getUIContext().px2vp(data.data!.width as number)
      Manager.height = this.getUIContext().px2vp(data.data!.height as number)
    })
    setInterval(() => {
      let infos = easytier.collectNetworkInfos()
      if (infos.length > 0) {
        let keys = new Set<string>
        infos.forEach((value: KeyValuePair) => {
          let info = JSON.parse(value.value) as NetworkInstanceRunningInfo
          Manager.infos.set(value.key, unwrappedEvents(info, value.key))
          keys.add(value.key)
        })
        for (const key of Manager.infos.keys()) {
          if (!keys.has(key)) {
            Manager.infos.delete(key);
          }
        }
      }else if (Manager.infos.size > 0) {
        Manager.infos.clear()
      }
       Manager.errorMsgs = entry.getErrorMsg()
    }, 100)
    if (canIUse("SystemCapability.BundleManager.AppLinking.DeferredLink")) {
      deferredLink.popDeferredLink().then((link: string) => {
        if (link) {
          readConfig(link).then(() => {
            this.getUIContext().getPromptAction().showToast({
              message: "成功导入分享的配置"
            })
          }, (reason:string) => {
            this.getUIContext().getPromptAction().showToast({
              message: "导入配置失败\n"+reason
            })
          })
        }
      }).catch((error: BusinessError) => {
        Logger.error(`Failed to get deferred link. code: ${error.code}, message: ${error.message}`);
      });
    }
  }

  changeSideBar(status: boolean = !this.showSideBar): void {
    animateToImmediately({
      duration: 300,
      curve: Curve.Friction,
      expectedFrameRateRange: {
        min: 30,
        max: 120,
        expected: 120
      }
    }, () => {
      this.showSideBar = status
    })
  }

  changeIndex(index: number): void {
    this.controller.changeIndex(index, true)
  }

  deleteConfig(config: Config, index: number) {
    animateToImmediately({
      duration: 300,
      curve: Curve.EaseIn
    }, () => {
      Manager.deleteConfig(config)
    })
    setTimeout(() => {
      if (index <= this.realIndex) {
        let target = Math.max(0, this.realIndex-1)
        Logger.debug("del config target:"+target)
        this.controller.changeIndex(target, true)
        this.realIndex = target
      }
    }, 100)
  }

  @Builder
  DeleteButton(config: Config, index: number) {
    ToolButton({
      symbol: $r("sys.symbol.trash_fill"),
      symbolColor: [$r("sys.color.warning")]
    })
      .margin({right: 10})
      .onClick(()=>{
        this.deleteConfig(config, index)
      })
  }

  @Builder
  QQGroupButton(text: string, qqgroup: string) {
    Row() {
      Text(text)
        .fontSize(17)
        .fontColor($r("sys.color.font_primary"))
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      Text(qqgroup)
        .fontSize(17)
        .fontColor($r("sys.color.font_primary"))
        .align(Alignment.Bottom)
    }
    .width('90%')
    .alignItems(VerticalAlign.Center)
    .justifyContent(FlexAlign.SpaceBetween)
    .backgroundColor($r("sys.color.comp_background_primary"))
    .padding({top: 12, bottom: 12, left: 12, right: 12})
    .borderRadius(18)
    .clickEffect({
      level: ClickEffectLevel.LIGHT
    })
    .onClick(() => {
      (this.getUIContext().getHostContext() as common.UIAbilityContext).startAbility({
        uri: "mqqapi://card/show_pslcard?src_type=internal&version=1&uin="+qqgroup+"&card_type=group&source=qrcode"
      })
    })
    .margin({top: 10})
  }
  @Builder
  ShareMenu() {
    Menu() {
      MenuItem({
        startIcon: $r("sys.symbol.dot_radiowaves_left_and_right"),
        content: "系统分享(可碰一碰)"
      })
        .onClick(() => {
          this.systemShareConfig()
        })
      MenuItemGroup({ header: '高级' }) {
        MenuItem({
          startIcon: $r("sys.symbol.doc_text"),
          content: "复制Toml"
        })
          .onClick(async () => {
            let config = Manager.getConfigs()[this.realIndex]
            if (config) {
              let pasteData: pasteboard.PasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, objectToHomoTOML(config));
              let systemPasteBoard: pasteboard.SystemPasteboard = pasteboard.getSystemPasteboard();
              await systemPasteBoard.setData(pasteData).catch((err: BusinessError) => {
                console.error(`Failed to set pastedata. Code: ${err.code}, message: ${err.message}`);
              });
            }else {
              this.getUIContext().getPromptAction().showToast({
                message: "先新增配置，才能分享喔"
              })
            }
          })
      }
    }
  }

  async systemShareConfig() {
    let config = Manager.getConfigs()[this.realIndex]
    if (config) {
      let shareData: systemShare.SharedData = new systemShare.SharedData({
        utd: utd.UniformDataType.HYPERLINK,
        content: 'https://easytier.cn/share_cfg?cfg='+(await compressedConfig(Manager.getConfigs()[this.realIndex])),
        title: config.instance_name,
        description: config.instance_id,
      });
      let controller: systemShare.ShareController = new systemShare.ShareController(shareData);
      let uiContext: UIContext = this.getUIContext();
      let context: common.UIAbilityContext = uiContext.getHostContext() as common.UIAbilityContext;
      controller.show(context, {
        selectionMode: systemShare.SelectionMode.SINGLE,
        previewMode: systemShare.SharePreviewMode.DEFAULT,
      })
    }else {
      this.getUIContext().getPromptAction().showToast({
        message: "先新增配置，才能分享喔"
      })
    }
  }

  build() {
    Stack({alignContent: Alignment.TopStart}) {
      SideBarContainer(SideBarContainerType.Overlay) {
        Column() {
          Column() {
            Text("实例列表")
              .fontSize(12)
              .margin({left: 10, bottom: 10})
              .fontColor($r("sys.color.font_secondary"))
              .width('90%')
            List() {
              ForEach(Array.from(Manager.configs.values()), (config: Config, index: number) => {
                ListItem() {
                  InstanceCard({
                    config: config,
                    bgColor: this.realIndex == index?$r("sys.color.interactive_focus"):$r("sys.color.comp_background_primary"),
                    fontColor: this.realIndex == index?$r("sys.color.font_on_primary"):$r("sys.color.font_primary"),
                    secondaryColor: this.realIndex == index?$r("sys.color.font_on_secondary"):$r("sys.color.font_secondary"),
                  })
                    .width('100%')
                    .margin({bottom: 5})
                    .onClick(() => {
                      this.changeIndex(index)
                    })
                }
                .swipeAction({
                  start: {
                    builder: () => {
                      this.DeleteButton(config, index) },
                    actionAreaDistance: 56,
                    onAction: () => {
                      this.deleteConfig(config, index)
                    },
                  }
                })
              }, (value:Config) => {return "index_configList_"+value.instance_id})
            }
            .maintainVisibleContentPosition(true)
            .alignListItem(ListItemAlign.Center)
            .width('90%')
            .height("40%")
            .borderRadius(18)
            .clip(true)
            .scrollBar(BarState.Off)
          }
          Column() {
            Text("联系方式")
              .fontSize(12)
              .margin({left: 10, top: 10})
              .fontColor($r("sys.color.font_secondary"))
              .width('90%')
            ForEach(Manager.qqgroups, (group: string, index) => {
              this.QQGroupButton("EasyTier"+(index+1)+"群", group)
            })
            this.QQGroupButton("AppBug反馈群", "630809530")
          }
        }
        .padding({top: 50})
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Start)
        .backgroundColor($r("sys.color.background_secondary"))
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.START, SafeAreaEdge.BOTTOM])
        .gesture(
          SwipeGesture({ direction: SwipeDirection.Horizontal })
            .onAction((event: GestureEvent|undefined) => {
              if(event && Math.abs(event.angle) > 90){
                this.changeSideBar(false)
              }
            })
        )
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.START, SafeAreaEdge.BOTTOM])

        Stack() {
          Column() {
            Row() {
              Text("晚安!")
                .fontColor($r("sys.color.font_primary"))
                .fontSize(24)
                .margin({left: 55})
              Row() {
                ToolButton({symbol: $r("sys.symbol.plus")})
                  .margin({right: 10})
                  .onClick(() => {
                    requestDistributePerm(this.getUIContext().getHostContext()!, false).then(() => {
                      this.addSheet = true
                    })
                  })
                  .bindSheet($$this.addSheet, AddSheet((value) => {
                    if (value) {
                      let config = tomlToConfig(value)
                      if (config) {
                        Manager.addConfig(config)
                      }else {
                        this.getUIContext().getPromptAction().showToast({
                          message: "导入失败\n导入文本为："+value
                        })
                      }
                      this.addSheet = false
                    }else {
                      this.getUIContext().getPromptAction().showToast({
                        message: "导入失败\n剪切板中没有内容！"
                      })
                    }
                  }, (value) => {
                    this.addSheet_name = value
                  }, this.addSheet_name), {
                    height: SheetSize.FIT_CONTENT,
                    preferType: SheetType.CENTER,
                    showClose: false,
                    dragBar: false,
                    blurStyle: BlurStyle.Thin,
                    title: AddSheetTitle(() => {
                      if (this.addSheet_name.match(/^\s*$/) === null) {
                        let config = new Config()
                        config.instance_name = this.addSheet_name
                        animateToImmediately({
                          duration: 300,
                          curve: Curve.EaseIn
                        }, () => {
                          Manager.addConfig(config)
                        })
                        setTimeout(() => {
                          let target = Manager.configs.size-1
                          this.controller.changeIndex(target, true)
                          this.realIndex = target
                        }, 100)
                      }
                      this.addSheet = false
                    }),
                    onDisappear: () => {
                      this.addSheet_name = ''
                    }
                  })
                ToolButton({symbol: $r("sys.symbol.cloud_and_arrow_down")})
                  .margin({right: 10})
                  .onClick(() => {
                    Manager.updateSharedPeers()
                    this.sharedPeersSheet = true
                  })
                  .bindSheet($$this.sharedPeersSheet, SharedPeersSheet(), {
                    height: SheetSize.LARGE,
                    preferType: SheetType.CENTER,
                    showClose: true,
                    dragBar: true,
                    blurStyle: BlurStyle.Thin,
                    title: SharedPeersTitle()
                  })
                ToolButton({symbol: $r("sys.symbol.rectangle_and_arrowshape_turn_up_right")})
                  .margin({right: 10})
                  .bindMenu(this.ShareMenu())
                ToolButton({symbol: $r("sys.symbol.gearshape")})
                  .onClick(() => {
                    this.setting = true
                  })
                  .margin({right: 10})
                  .bindSheet($$this.setting, settingSheet(this.getUIContext().getHostContext()!), {
                    height: SheetSize.LARGE,
                    preferType: SheetType.CENTER,
                    showClose: true,
                    dragBar: true,
                    blurStyle: BlurStyle.Thin,
                    title: {
                      title: "设置"
                    },
                  })
              }
              .height(40)
              .justifyContent(FlexAlign.SpaceAround)
            }
            .width('100%')
            .alignItems(VerticalAlign.Center)
            .align(Alignment.Start)
            .height(40)
            .margin({top: 5})
            .justifyContent(FlexAlign.SpaceBetween)
            if (Manager.configs.size == 0) {
              Stack({alignContent: Alignment.TopStart}) {
                Line()
                  .zIndex(3)
                  .startPoint([30,5])
                  .endPoint([30,30])
                  .strokeWidth(3)
                  .strokeLineCap(LineCapStyle.Round)
                  .width('100%')
                  .height('100%')
                  .stroke($r("sys.color.font_tertiary"))
                Line()
                  .zIndex(3)
                  .startPoint([Manager.width-130,5])
                  .endPoint([Manager.width-130,30])
                  .strokeWidth(3)
                  .strokeLineCap(LineCapStyle.Round)
                  .width('100%')
                  .height('100%')
                  .stroke($r("sys.color.font_tertiary"))
                Text("侧边栏\n可以在实例列表切换实例\n也可以跳转QQ群")
                  .fontColor($r("sys.color.font_tertiary"))
                  .fontSize(12)
                  .offset({
                    x: 10,
                    y: 33
                  })
                Text("社区共享节点\n可以直接导入社区节点使用")
                  .fontColor($r("sys.color.font_tertiary"))
                  .fontSize(12)
                  .offset({
                    x: Manager.width-166,
                    y: 33
                  })
              }
              .width('100%')
              .height('100%')
            }else {
              Swiper(this.controller){
                ForEach(Array.from(Manager.configs.values()), (config: Config) => {
                  Stack() {
                    InstanceCard({config: config, bgColor: $r("app.color.blurBG"), blurRadius: 100 })
                      .zIndex(3)
                    if (!Manager.infos.has(config.instance_id)) {
                      InstanceContent({config: config})
                        .zIndex(2)
                    }else {
                      InstanceStatus({config: config})
                        .zIndex(2)
                    }
                  }
                  .borderRadius(18)
                  .width('100%')
                  .height('100%')
                  .alignContent(Alignment.Top)
                  .clip(true)
                }, (value:Config) => {return "index_swiper_"+value.instance_id})
              }
              .width('100%')
              .height('100%')
              .itemSpace(10)
              .indicator(false)
              .effectMode(EdgeEffect.Spring)
              .onAnimationStart((_index, targetIndex) => {
                animateToImmediately({
                  curve: Curve.EaseIn,
                  duration: 300
                }, () => {
                  Logger.debug("setup realIndex:"+targetIndex)
                  this.realIndex = targetIndex
                })
              })
              .padding({left: 10, right: 10})
              .margin({top: 10})
            }
          }
          .margin({left:10, right:10})
          .width('100%')
          .height('100%')
          .alignItems(HorizontalAlign.Start)
          .align(Alignment.Center)
          .zIndex(2)
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
          if (this.showSideBar) Column()
            .alignItems(HorizontalAlign.Center)
            .justifyContent(FlexAlign.Center)
            .backgroundColor(Color.Black)
            .opacity(0.4)
            .height('100%')
            .width('100%')
            .zIndex(3)
            .onClick(() => {
              this.changeSideBar(false)
            })
            .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
        }
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      }
      .showControlButton(false)
      .width('100%')
      .height('100%')
      .zIndex(1)
      .sideBarWidth('80%')
      .minSideBarWidth(Manager.width*0.8)
      .showSideBar($$this.showSideBar)
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      Row() {
        ToolButton({symbol: this.showSideBar?$r("sys.symbol.indentation_left"):$r("sys.symbol.indent_right")})
          .onClick(() => {
            this.changeSideBar()
          })
      }
      .alignItems(VerticalAlign.Center)
      .align(Alignment.Start)
      .height(40)
      .margin({left: 10, top: 5})
      .zIndex(4)
    }
    .width("100%")
    .height("100%")
    .backgroundColor($r("sys.color.background_secondary"))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}