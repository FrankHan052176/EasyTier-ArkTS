import Manager, { UIType } from '../Manager';
import EventHelper from '../util/EventHelper';
import { AddSheetTitle, cleanNewConfigName } from '../util/AddConfigSheet';
import { systemDateTime } from '@kit.BasicServicesKit';
import { fp2vp, laneWidth, laneHeight, logColor } from '../util/Conversion';
import { LengthMetrics } from '@kit.ArkUI';
import { Config, SharedPeer } from '../util/config/ETConfig';
import { ItemBuilder } from '../util/ItemBuilders';
import { AddConfig } from '../util/AddConfigSheet';
import { MenuButton, ResizableComponent, settingSheet, ToolButton } from './Components';
import Logger from '../util/Logger';
import { requestDistributePerm } from '../util/Permission';
import { InstanceContent } from './instance/InstanceContent';
import { common } from '@kit.AbilityKit';
import { AutoSortContainer } from './nodes/AutoSortContainer';

@Extend(Column)
function comp_bg(lane: number, height: number) {
  .clickEffect({
    level: ClickEffectLevel.LIGHT
  })
  .borderRadius(18)
  .width(laneWidth(lane))
  .height(laneHeight(height))
  .backgroundColor($r("sys.color.comp_background_primary"))
  .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
}
@Extend(List)
function comp_list() {
  .onTouch((event) => event.stopPropagation())
  .maintainVisibleContentPosition(true)
  .alignListItem(ListItemAlign.Center)
  .width('100%')
  .scrollBar(BarState.Off)
  .fadingEdge(true, { fadingEdgeLength: LengthMetrics.vp(20) })
  .chainAnimation(true)
  .scrollSnapAlign(ScrollSnapAlign.START)
  .animation({
    duration: 200,
    curve: Curve.EaseIn
  })
}
@Entry
@ComponentV2
struct NavIndex {
  @Provider('pageStack') pageStack: NavPathStack = new NavPathStack();
  private myNodeController: AutoSortContainer = new AutoSortContainer();
  @Local add_config_sheet: boolean = false
  @Local select: Config | string = "unselected"
  @Local title_width: number = 0
  @Local edit: boolean = false
  @Local log: boolean = false
  @Local log_index: number = 0
  @Local setting: boolean = false
  @Local edit_uuid: string | undefined
  @Local lane_h: number = 1
  @Local lane_w: number = 1

  @Builder
  PageMap(name: string, param?: object) {
    if (name === "EDIT") {

    }else if (name === "STATUS") {

    }else if (name === "SETTING") {

    }else if (name === "INSTANCES") {

    }else if (name === "PEERS") {

    }else if (name === "LOG") {

    }else if (name === "GLOBAL") {

    }
  }

  @Builder
  gradientText(size: number = 36, text: string | Resource | undefined = 'EasyTier', weight: number | FontWeight | ResourceStr = FontWeight.Bold, angle: string | number | undefined = 225) {
    Stack() {
      Text(text)
        .fontWeight(weight)
        .fontSize(size)
        .fontColor(Color.Transparent)
        .textShadow({
          radius: 1,
          color: $r("sys.color.font_on_primary")
        })
      Row() {
        Text(text)
          .fontWeight(weight)
          .fontSize(size)
          .blendMode(BlendMode.DST_IN, BlendApplyType.OFFSCREEN)
      }
      .linearGradient({
        colors:[
          ['rgba(255,200,50,1)', 0.3],
          ['rgba(0,230,118,1)', 1]
        ],
        angle: angle
      })
      .blendMode(BlendMode.SRC_OVER, BlendApplyType.OFFSCREEN)
      .justifyContent(FlexAlign.Center)
    }
  }

  @Computed
  get greeting() {
    const date = new Date(systemDateTime.getTime());
    const hours = date.getHours();
    if (hours >= 5 && hours < 12) {
      return "早上好";
    } else if (hours >= 12 && hours < 14) {
      return "中午好";
    } else if (hours >= 14 && hours < 18) {
      return "下午好";
    } else if (hours >= 18 && hours < 22) {
      return "晚上好";
    } else {
      return "夜深了";
    }
  }

  @Builder
  PageTitle() {
    Row() {
      Text(this.greeting)
        .fontColor($r("sys.color.font_primary"))
        .fontWeight(FontWeight.Bold)
        .fontSize(32)
    }
    .padding({left: 16})
    .alignItems(VerticalAlign.Center)
    .justifyContent(FlexAlign.Start)
    .width('100%')
    .height('100%')
  }

  @Builder
  CompTitle(title: string, color: ResourceColor, sizeFunc: () => number, ge: Resource = $r("app.string.i18_ge"), needCnt: boolean = true) {
    Row() {
      Row() {
        Divider().vertical(true).color(color).strokeWidth(5).lineCap(LineCapStyle.Round).height('70%')
        Text(title).fontSize(22).fontColor($r("sys.color.font_primary")).margin({left: 5})
      }
      Row() {
        if (needCnt) {
          Text($r("app.string.i18_total")).fontSize(10).fontColor($r("sys.color.font_primary"))
          Text(""+sizeFunc()).fontSize(20).fontColor($r("sys.color.font_primary"))
          Text(ge).fontSize(10).fontColor($r("sys.color.font_primary"))
        }
      }
      .height('100%')
      .alignItems(VerticalAlign.Bottom)
    }
    .height(fp2vp(22))
    .justifyContent(FlexAlign.SpaceBetween)
    .padding({left: 10, right: 15})
    .margin({top: 15, bottom: 5})
    .width('100%')
  }

  deleteConfig(config: Config) {
    animateToImmediately({
      duration: 300,
      curve: Curve.EaseIn
    }, () => {
      Manager.deleteConfig(config)
    })
  }

  @Builder
  DeleteButton(callback: () => void) {
    ToolButton({
      symbol: $r("sys.symbol.trash_fill"),
      symbolColor: [$r("sys.color.warning")]
    })
      .margin({left: 10})
      .onClick(()=>{
        callback()
      })
  }

  @Builder
  RightButtons(callback1: () => void, callback2: () => void, auto_start: boolean) {
    Row() {
      ToolButton({
        symbol: $r("sys.symbol.doc_plaintext_and_pencil"),
        symbolColor: [$r("sys.color.font_primary")]
      })
        .margin({right: 10})
        .onClick(()=>{
          callback1()
        })
      ToolButton({
        symbol: auto_start?$r("sys.symbol.star_fill"):$r("sys.symbol.star"),
        symbolColor: [$r("sys.color.confirm")]
      })
        .margin({right: 10})
        .onClick(()=>{
          callback2()
        })
    }
  }

  @Builder
  LogShower(symbol: Resource, name: string, sizeFunc: () => number, index: number) {
    Row() {
      Row() {
        Text() {
          SymbolSpan(symbol)
            .fontSize(16)
            .fontColor([$r("sys.color.font_primary")])
        }
        .margin({right: 5})
        Text(name)
          .fontColor($r("sys.color.font_primary"))
      }
      Row() {
        Text(""+sizeFunc()).fontSize(14).fontColor($r("sys.color.font_primary"))
        Text($r("app.string.i18_tiao")).fontSize(10).fontColor($r("sys.color.font_primary"))
      }
      .alignItems(VerticalAlign.Bottom)
    }
    .width('100%')
    .alignItems(VerticalAlign.Bottom)
    .justifyContent(FlexAlign.SpaceBetween)
    .onClick(() => {
      this.log_index = index
      this.log = true
    })
  }

  aboutToAppear(): void {
    Manager.uiContext = this.getUIContext()
    Manager.onInit()
    EventHelper.emitterListener("sheet_add_config_close", () => {
      this.add_config_sheet = false
    })
  }

  @Builder
  Comp_Title() {
    Column() {
      Row() {
        this.gradientText(48)
        this.gradientText(16, "v2.4.5", FontWeight.Normal, 135)
      }
      .alignItems(VerticalAlign.Bottom)
      .justifyContent(FlexAlign.Center)
      .geometryTransition("easytier_text")
      .onAreaChange((a,b) => {
        this.title_width = b.width.valueOf() as number
      })
      .margin({bottom: 10})
      if (this.select != "unselected") {
        ItemBuilder({item: this.select, isSelected: true, itemWidth: this.title_width, itemHeight: 60, shadowRadius: 25})
          .transition(TransitionEffect.scale({
            x: 0,
            y: 0
          }))
      }
    }
    .width(laneWidth(6))
    .height(laneHeight(1))
    .alignItems(HorizontalAlign.Center)
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  editSheet() {
    Column() {
      InstanceContent({config: Manager.configs.get(this.edit_uuid!)!, comp_height: '100%'})
    }
  }

  @Computed
  get isNeedHideButtons() {
    return Manager.uiType == UIType.Column_1
  }

  @Builder
  configButtons(config: Config, show: boolean) {
    if (show) {
      this.RightButtons(
        () => {
          this.edit_uuid = config.instance_id
          this.edit = true
        },
        () => {Manager.updateAutoStart(config.instance_id)},
        Manager.auto_start == config.instance_id
      )
    }
  }

  @Builder
  Comp_Instances() {
    Column() {
      this.CompTitle("实例", 'rgba(0,230,118,1)', ()=>{return Manager.configs.size})
      List({space: 8}) {
        ForEach(Array.from(Manager.configs.values()), (config: Config, index: number) => {
          ListItem() {
            ItemBuilder({item: config, isSelected: this.select === config, itemWidth: '100%', itemHeight: 50, shadowRadius: 25, config_buttons: () => {
              this.configButtons(config, !this.isNeedHideButtons)
            }})
              .onClick(() => {
                animateToImmediately({
                  duration: 300,
                  curve: Curve.EaseIn
                }, () => {
                  if (this.select === config) {
                    this.select = "unselected"
                  }else {
                    this.select = config
                  }
                })
              })
              .geometryTransition("config_"+config.instance_id)
              .margin({left: 10, right: 10, top: index==0?5:0, bottom: Manager.configs.size-1==index?10:0})
          }
          .width('100%')
          .swipeAction({
            start: {
              builder: this.DeleteButton(() => {this.deleteConfig(config)}),
              actionAreaDistance: 36,
              onAction: () => {
                this.deleteConfig(config)
              },
            },
            end: {
              builder: () => {
                if (this.isNeedHideButtons) {
                  this.RightButtons(
                    () => {
                      this.edit_uuid = config.instance_id
                      this.edit = true
                    },
                    () => {Manager.updateAutoStart(config.instance_id)},
                    Manager.auto_start == config.instance_id
                  )
                }
              },
              actionAreaDistance: 56
            }
          })
        }, (value:Config) => {return "index_configs_"+value.instance_id})
      }
      .comp_list()
      .bindSheet($$this.edit, this.editSheet(),{
        height: SheetSize.LARGE,
        preferType: SheetType.CENTER,
        showClose: true,
        dragBar: true,
        title: {
          title: "编辑"
        },
        blurStyle: BlurStyle.Thin,
        onDisappear: () => {
          this.edit_uuid = undefined
        }
      })
    }
    .comp_bg(this.lane_w,this.lane_h)
    .geometryTransition("instances")
  }

  @Builder
  Comp_Peers() {
    Column() {
      this.CompTitle("社区共享", 'rgba(255,200,50,1)', ()=>{return Manager.sharedPeers.size})
      List({space: 8}) {
        LazyForEach(Manager.sharedPeers, (peer: SharedPeer, index: number) => {
          ListItem() {
            ItemBuilder({item: peer, isSelected: peer.isEnabled(), itemWidth: '100%', itemHeight: 50, shadowRadius: 25})
              .onClick(() => {
                peer.changeEnabled()
              })
              .margin({left: 10, right: 10, top: index==0?5:0, bottom: Manager.sharedPeers.size-1==index?10:0})
              .geometryTransition("shared_peer"+peer.toShortString())
          }
          .width('100%')
        }, (peer:SharedPeer) => {return "index_shared_peer_"+peer.toShortString()})
      }
      .comp_list()
    }
    .comp_bg(1,1)
  }

  @Builder
  logSheet() {
    Tabs({index: $$this.log_index}) {
      TabContent() {
        List() {
          if (Manager.appLogs.size > 0) {
            ForEach(Array.from(Manager.appLogs.values()), (msg: string) => {
              ListItem() {
                Text(msg.substring(1))
                  .fontSize(14)
                  .width("100%")
                  .fontColor(logColor(msg))
              }
            })
            ListItem()
              .height(100)
              .width('100%')
          }else {
            ListItem() {
              Text("无日志")
                .fontSize(14)
                .width("100%")
            }
          }
        }
        .scrollBar(BarState.Off)
        .alignListItem(ListItemAlign.Start)
        .padding({left: 10, right: 10})
        .clip(true)
        .borderRadius(18)
        .width("100%")
        .height("100%")
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.START, SafeAreaEdge.BOTTOM])
      }
      .tabBar("App日志")
      TabContent() {
        List() {
          if (Manager.nmLogs.size > 0) {
            ForEach(Array.from(Manager.nmLogs.values()), (msg: string) => {
              ListItem() {
                Text(msg.substring(1))
                  .fontSize(14)
                  .width("100%")
                  .fontColor(logColor(msg))
              }
            })
            ListItem()
              .height(100)
              .width('100%')
          }else {
            ListItem() {
              Text("无日志")
                .fontSize(14)
                .width("100%")
            }
          }
        }
        .scrollBar(BarState.Off)
        .alignListItem(ListItemAlign.Start)
        .padding({left: 10, right: 10})
        .clip(true)
        .borderRadius(18)
        .width("100%")
        .height("100%")
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.START, SafeAreaEdge.BOTTOM])
      }
      .tabBar("网络日志")
      TabContent() {
        List() {
          if (Manager.ohLogs.size > 0) {
            ForEach(Array.from(Manager.ohLogs.values()), (msg: string) => {
              ListItem() {
                Text(msg.substring(1))
                  .fontSize(14)
                  .width("100%")
                  .fontColor(logColor(msg))
              }
            })
            ListItem()
              .height(100)
              .width('100%')
          }else {
            ListItem() {
              Text("无日志")
                .fontSize(14)
                .width("100%")
            }
          }
        }
        .scrollBar(BarState.Off)
        .alignListItem(ListItemAlign.Start)
        .padding({left: 10, right: 10})
        .clip(true)
        .borderRadius(18)
        .width("100%")
        .height("100%")
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.START, SafeAreaEdge.BOTTOM])
      }
      .tabBar("ArkUI日志")
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  Comp_Logs() {
    Column() {
      this.CompTitle("日志", $r("sys.color.font_primary"), ()=>{return Manager.appLogs.size+Manager.nmLogs.size+Manager.ohLogs.size}, $r("app.string.i18_tiao"))
      Column({space: 10}) {
        this.LogShower($r("sys.symbol.house"), "App日志", ()=>{return Manager.appLogs.size}, 0)
        this.LogShower($r("sys.symbol.wifi"), "网络日志", ()=>{return Manager.nmLogs.size}, 1)
        this.LogShower($r("sys.symbol.HarmonyOS"), "ArkUI日志", ()=>{return Manager.ohLogs.size}, 2)
      }
      .width('100%')
      .layoutWeight(100)
      .padding({left: 10, right: 10, top: 10, bottom: 10})
    }
    .comp_bg(1,1)
    .onClick(() => {
      this.log = true
    })
    .bindSheet($$this.log, this.logSheet(),{
      height: SheetSize.LARGE,
      preferType: SheetType.CENTER,
      showClose: true,
      dragBar: true,
      title: {
        title: "日志"
      },
      blurStyle: BlurStyle.Thin
    })
  }

  @Builder
  Comp_Last() {
    Column() {
      this.CompTitle("最近启动", 'rgba(255,200,50,1)', ()=>{return 0}, $r("app.string.i18_tiao"), false)
      Column() {

      }
      .width('100%')
      .layoutWeight(100)
      .padding({left: 10, right: 10, top: 10})
    }
    .comp_bg(1,1)
  }

  @Builder
  Global_Content(symbol: Resource, name: string | Resource, sizeFunc: () => number) {
    Row() {
      Row() {
        Text() {
          SymbolSpan(symbol).fontColor([$r("sys.color.font_primary")]).fontSize(16)
        }
        .margin({right: 5})
        Text(name).maxLines(1).fontColor($r("sys.color.font_primary"))
      }
      Row() {
        Row() {
          Text(""+sizeFunc()).fontSize(14).fontColor($r("sys.color.font_primary"))
          Text($r("app.string.i18_tiao")).fontSize(10).fontColor($r("sys.color.font_primary"))
        }
        .alignItems(VerticalAlign.Bottom)
      }
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .justifyContent(FlexAlign.SpaceBetween)
  }

  @Builder
  Comp_Global() {
    Column() {
      this.CompTitle("全局配置", $r("sys.color.font_primary"), ()=>{return 0}, $r("app.string.i18_ge"), false)
      Column({space: 5}) {
        this.Global_Content($r('sys.symbol.worldclock'),"Peers",()=>{return Manager.peers.size})
        this.Global_Content($r('sys.symbol.person'),"凭证",()=>{return Manager.network_identities.size})
        this.Global_Content($r('sys.symbol.position'),"监听地址",()=>{return Manager.listeners.size})
        this.Global_Content($r('sys.symbol.list_bullet'),"自定义路由",()=>{return Manager.routes.size})
        this.Global_Content($r('sys.symbol.list_bullet'),"子网代理",()=>{return Manager.cidrs.size})
        this.Global_Content($r('sys.symbol.local_fill'),"出口节点",()=>{return Manager.exit_nodes.size})
        this.Global_Content($r('sys.symbol.person'),"网络白名单",()=>{return Manager.whitelist.size})
      }
      .width('100%')
      .layoutWeight(100)
      .padding({left: 10, right: 10, top: 10, bottom: 10})
    }
    .comp_bg(1,1)
  }

  @Builder
  QQ_Content(symbol: Resource, name: string | Resource, qqgroup: string) {
    Row() {
      Row() {
        Text() {
          SymbolSpan(symbol).fontColor([$r("sys.color.font_primary")]).fontSize(16)
        }
        .margin({right: 5})
        Text(name).maxLines(1).fontColor($r("sys.color.font_primary"))
      }
      Row() {
      }
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .justifyContent(FlexAlign.SpaceBetween)
    .onClick(() => {
      (this.getUIContext().getHostContext() as common.UIAbilityContext).startAbility({
        uri: "mqqapi://card/show_pslcard?src_type=internal&version=1&uin="+qqgroup+"&card_type=group&source=qrcode"
      }).catch(() => {
        Logger.error(`[Index] QQGroupButton::An unexpected error occurred.`);
      })
    })
  }

  @Builder
  Comp_QQ() {
    Column() {
      this.CompTitle("QQ群", $r("sys.color.brand"), ()=>{return 0}, $r("app.string.i18_tiao"), false)
      Column({space: 10}) {
        ForEach(Manager.qqgroups, (qqgroup: string, index: number) => {
          this.QQ_Content($r("sys.symbol.message_on_message"), "EasyTier"+(index+1)+"群", qqgroup)
        })
        this.QQ_Content($r("sys.symbol.message_on_message"), "App反馈群", "630809530")
      }
      .width('100%')
      .layoutWeight(100)
      .padding({left: 10, right: 10, top: 10, bottom: 10})
    }
    .comp_bg(1,1)
  }

  build() {
    Navigation(this.pageStack) {
      Column() {
        Scroll() {
          Column() {
            this.Comp_Title()
            // Flex({wrap: FlexWrap.Wrap, direction: FlexDirection.Row,
            //   space: {
            //     main: LengthMetrics.vp(10),
            //     cross: LengthMetrics.vp(10)
            //   }
            // }) {
            //   ResizableComponent()
            //   this.Comp_Instances()
            //   this.Comp_Last()
            //   this.Comp_QQ()
            //   this.Comp_Logs()
            //   this.Comp_Peers()
            //   this.Comp_Global()
            // }
            // .padding({left: 20, right: 20})
            // .width('100%')
            // .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
            NodeContainer(this.myNodeController)
              .width('100%')
              .layoutWeight(100)
              .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
          }
          .width('100%')
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
        }
        .scrollBar(BarState.Off)
        .width('100%')
        .height('100%')
        .align(Alignment.Top)
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      }
      .width('100%')
      .height('100%')
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      .onAreaChange((a,b) => {
        Manager.compHeight = b.height.valueOf() as number
      })
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
    .navDestination(this.PageMap)
    .mode(NavigationMode.Stack)
    .backgroundColor($r("sys.color.background_secondary"))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .height('100%')
    .width('100%')
    .bindSheet($$this.add_config_sheet, AddConfig(), {
      height: SheetSize.FIT_CONTENT,
      preferType: SheetType.CENTER,
      showClose: false,
      dragBar: false,
      blurStyle: BlurStyle.Thin,
      title: AddSheetTitle(),
      onDisappear: () => {
        cleanNewConfigName()
      }
    })
    .title(this.PageTitle())
    .titleMode(NavigationTitleMode.Mini)
    .hideBackButton(true)
    .menus([
      MenuButton("add", $r("sys.symbol.plus"), () => {
        requestDistributePerm(this.getUIContext().getHostContext()!, false).then(() => {
          this.add_config_sheet = true
        })
      }),
      MenuButton("add", $r("sys.symbol.gearshape"), () => {
        this.setting = true
      }),
    ])
    .onAreaChange((a,b) => {
      Manager.navigationHeight = b.height.valueOf() as number
    })
    .onTouch((event) => {
      if (event && event.type == TouchType.Down) {
        EventHelper.emitterPublish("resize_off")
      }
    })
  }
}