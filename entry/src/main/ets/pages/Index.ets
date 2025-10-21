import Manager, { UIType } from '../Manager'
import { Config } from '../util/config/ETConfig'
import {
  AddSheet,
  AddSheetTitle,
  settingSheet,
  SharedPeersSheet,
  SharedPeersTitle, ToolButton } from './Components'
import { InstanceCard } from './instance/InstanceCard'
import { InstanceContent } from './instance/InstanceContent'
import { requestDistributePerm, updatePermStatus } from '../util/Permission'
import { objectToHomoTOML, tomlToConfig } from '../util/Conversion'
import EventHelper from '../util/EventHelper'
import { InstanceStatus } from './instance/InstanceStatus'
import { harmonyShare, systemShare } from '@kit.ShareKit';
import { uniformTypeDescriptor as utd } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { BusinessError, pasteboard } from '@kit.BasicServicesKit';
import Logger from '../util/Logger'
import { compressedConfig, readConfig } from '../util/Compress'
import { deferredLink } from '@kit.AppLinkingKit'
import { deviceInfo } from '@kit.BasicServicesKit';
import { ItemBuilder } from '../util/ItemBuilders'

@Entry
@ComponentV2
struct Index {
  @Local realIndex: number = 0
  @Local showSideBar: boolean = false
  @Local addSheet: boolean = false
  @Local importSheet: boolean = false
  @Local shareMenu: boolean = false
  @Local sharedPeersSheet: boolean = false
  @Local setting: boolean = false
  @Local addSheet_name: string = ""

  private async immersiveCallback(sharableTarget: harmonyShare.SharableTarget) {
    let shareData: systemShare.SharedData = new systemShare.SharedData({
      utd: utd.UniformDataType.HYPERLINK,
      content: 'https://easytier.cn/share_cfg_'+(await compressedConfig(Manager.getConfigs()[this.realIndex])),
      title: '分享配置 '+Manager.getConfigs()[this.realIndex].instance_name,
      description: Manager.getConfigs()[this.realIndex].instance_id
    });
    sharableTarget.share(shareData);
  }

  onPageShow(): void {
    if (deviceInfo.sdkApiVersion >= 20) {
      harmonyShare.on('gesturesShare', this.immersiveCallback);
    }
  }

  onPageHide(): void {
    if (deviceInfo.sdkApiVersion >= 20) {
      harmonyShare.off('gesturesShare', this.immersiveCallback);
    }
  }

  aboutToAppear(): void {
    Manager.uiContext = this.getUIContext()
    Manager.onInit()
  }

  changeSideBar(status: boolean = !this.showSideBar): void {
    animateToImmediately({
      duration: 300,
      curve: Curve.Friction
    }, () => {
      this.showSideBar = status
    })
  }

  changeIndex(index: number): void {
    this.realIndex = index
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
        this.realIndex = Math.max(0, this.realIndex-1)
      }
    }, 100)
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
    .width('100%')
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
      }).catch(() => {
        Logger.error(`[Index] QQGroupButton::An unexpected error occurred.`);
      })
    })
    .margin({top: 10})
  }

  @Builder
  DeleteButton(callback: () => void) {
    ToolButton({
      symbol: $r("sys.symbol.trash_fill"),
      symbolColor: [$r("sys.color.warning")]
    })
      .margin({right: 10})
      .onClick(()=>{
        callback()
      })
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
              try {
                this.getUIContext().getPromptAction().showToast({
                  message: "先新增配置，才能分享喔"
                })
              } catch (e) {
                Logger.error(`[Index] An unexpected error occurred. Code:${e.code},message:${e.message}`);
              }
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
      }).catch(() => {
        Logger.error(`[Index] systemShareConfig::An unexpected error occurred.`);
      })
    }else {
      try {
        this.getUIContext().getPromptAction().showToast({
          message: "先新增配置，才能分享喔"
        })
      } catch (e) {
        Logger.error(`[Index] An unexpected error occurred. Code:${e.code},message:${e.message}`);
      }
    }
  }

  pastCallback(value: string | undefined) {
    if (value) {
      let config = tomlToConfig(value)
      if (config) {
        Manager.addConfig(config)
      }else {
        try {
          this.getUIContext().getPromptAction().showToast({
            message: "导入失败\n导入文本为：" + value
          })
        } catch (e) {
          Logger.error(`[Index] An unexpected error occurred. Code:${e.code},message:${e.message}`);
        }
      }
      this.addSheet = false
    }else {
      try {
        this.getUIContext().getPromptAction().showToast({
          message: "导入失败\n剪切板中没有内容！"
        })
      } catch (e) {
        Logger.error(`[Index] An unexpected error occurred. Code:${e.code},message:${e.message}`);
      }
    }
  }

  @Builder
  sideBar() {
    Column() {
      Column() {
        Text("实例列表")
          .fontSize(12)
          .padding({left: 10, bottom: 10})
          .fontColor($r("sys.color.font_secondary"))
          .width('100%')
        List({space: 5}) {
          ForEach(Array.from(Manager.configs.values()), (config: Config, index: number) => {
            ListItem() {
              ItemBuilder({item: config, isSelected: this.realIndex == index, itemWidth: '100%', itemHeight: 60, shadowRadius: 0})
                .onClick(() => {
                  this.changeIndex(index)
                })
                .geometryTransition("instance_card_"+config.instance_id)
            }
            .swipeAction({
              start: {
                builder: () => {
                  this.DeleteButton((): void => {
                    this.deleteConfig(config, index);
                  }) },
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
        .width('100%')
        .height('100%')
        .clip(true)
        .scrollBar(BarState.Off)
      }
      .layoutWeight(100)
      Column() {
        Text("联系方式")
          .fontSize(12)
          .padding({left: 10, top: 10})
          .fontColor($r("sys.color.font_secondary"))
          .width('100%')
        ForEach(Manager.qqgroups, (group: string, index) => {
          this.QQGroupButton("EasyTier"+(index+1)+"群", group)
        })
        this.QQGroupButton("AppBug反馈群", "630809530")
      }
      .width('100%')
      .margin({bottom: 20})
      .height(Manager.qqgroups.length*53+53+44)
      .clip(true)
    }
    .padding({top: Manager.uiType != UIType.Column_3?55:0, right: 10, left: Manager.uiType != UIType.Column_3?10:0})
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Start)
    .backgroundColor($r("sys.color.background_secondary"))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.START, SafeAreaEdge.BOTTOM])
    .gesture(
      SwipeGesture({ direction: SwipeDirection.Horizontal })
        .onAction((event: GestureEvent|undefined) => {
          if(Manager.uiType != UIType.Column_3 || (event && Math.abs(event.angle) > 90)){
            this.changeSideBar(false)
          }
        })
    )
    .transition(TransitionEffect.move(TransitionEdge.START))
  }

  build() {
    Stack({alignContent: Alignment.TopStart}) {
      SideBarContainer(SideBarContainerType.Overlay) {
        this.sideBar()
        Stack() {
          Column() {
            Row() {
              Text("晚安!")
                .fontColor($r("sys.color.font_primary"))
                .fontSize(24)
                .margin({left: Manager.uiType != UIType.Column_3?55:15})
              Row() {
                ToolButton({symbol: $r("sys.symbol.plus")})
                  .margin({right: 10})
                  .onClick(() => {
                    requestDistributePerm(this.getUIContext().getHostContext()!, false).then(() => {
                      this.addSheet = true
                    })
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
                  .bindSheet($$this.setting, settingSheet(), {
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
              .height('100%')
              .justifyContent(FlexAlign.SpaceAround)
            }
            .width('100%')
            .alignItems(VerticalAlign.Center)
            .align(Alignment.Start)
            .height(40)
            .margin({top: 5})
            .justifyContent(FlexAlign.SpaceBetween)
            .bindSheet($$this.addSheet, AddSheet((value) => {
              this.pastCallback(value)
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
                    this.realIndex = Manager.configs.size-1
                  }, 100)
                }
                this.addSheet = false
              }),
              onDisappear: () => {
                this.addSheet_name = ''
              }
            })
            if (Manager.configs.size == 0) {
              Stack({alignContent: Alignment.TopStart}) {
                if (Manager.uiType == UIType.Column_3) {
                  Row() {
                    Column() {
                      this.sideBar()
                    }
                    .width('20%')
                  }
                  .zIndex(3)
                  .width('100%')
                  .height('100%')
                  .alignItems(VerticalAlign.Center)
                  .justifyContent(FlexAlign.Start)
                }
                Line()
                  .zIndex(3)
                  .startPoint([Manager.width-130,5])
                  .endPoint([Manager.width-130,30])
                  .strokeWidth(3)
                  .strokeLineCap(LineCapStyle.Round)
                  .width('100%')
                  .height('100%')
                  .stroke($r("sys.color.font_tertiary"))
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
              Stack() {
                if (Manager.uiType != UIType.Column_3) {
                  InstanceCard({config: Manager.getConfigs()[this.realIndex]})
                    .zIndex(3)
                    .margin({top: 5})
                    .geometryTransition("instance_card_"+Manager.getConfigs()[this.realIndex].instance_id)
                }
                Row() {
                  if (Manager.uiType == UIType.Column_3) {
                    Column() {
                      this.sideBar()
                    }
                    .height('100%')
                    .layoutWeight(20)
                  }
                  if (Manager.info_uuid != Manager.getConfigs()[this.realIndex].instance_id) {
                    InstanceContent({config: Manager.getConfigs()[this.realIndex]})
                      .height('100%')
                      .zIndex(2)
                      .layoutWeight(80)
                  }else {
                    InstanceStatus({config: Manager.getConfigs()[this.realIndex]})
                      .height('100%')
                      .zIndex(2)
                      .layoutWeight(80)
                  }
                }
                .margin({top: Manager.uiType != UIType.Column_3?66:0})
                .width('100%')
                .height('100%')
              }
              .borderRadius(18)
              .width('100%')
              .height('100%')
              .alignContent(Alignment.Top)
              .clip(true)
              .padding({left: 10, right: 10})
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
      if (Manager.uiType != UIType.Column_3) {
        Row() {
          ToolButton({symbol: this.showSideBar?$r("sys.symbol.indentation_left"):$r("sys.symbol.indent_right")})
            .onClick(() => {
              this.changeSideBar()
            })
        }
        .alignItems(VerticalAlign.Center)
        .justifyContent(FlexAlign.Start)
        .height(40)
        .margin({left: 10, top: 5})
        .zIndex(4)
      }
    }
    .width("100%")
    .height("100%")
    .backgroundColor($r("sys.color.background_secondary"))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}