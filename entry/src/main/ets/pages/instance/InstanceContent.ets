import { cidr, Config,
  exit_node,
  listener, network_identity, peer, route, WrappedString } from "../../util/ETConfig"
import { Hostname } from "../content/Hostname"
import { IPv4 } from "../content/IPv4"
import { LengthUnit } from "@kit.ArkUI"
import Manager from "../../Manager"
import { Flags } from "../content/Flags"
import { WGPortal } from "../content/WGPortal"
import { Socks5 } from "../content/Socks5"
import { FlexItems, ItemSize, itemType } from "../content/FlexItems"
import { SafeLightWeightSet } from "../../util/SafeLightWeightSet"
import { Logger } from "../../util/Logger"
import { UIType, WindowUtil } from "../../WindowUtil"

const space: FlexSpaceOptions = {
  main: {
    value: 10,
    unit: LengthUnit.VP
  },
  cross: {
    value: 10,
    unit: LengthUnit.VP
  }
}

@ComponentV2
export struct InstanceContent {
  @Param @Require config:Config
  @Param comp_height: Length = WindowUtil.height-95
  @Local realWidth: number = 0

  get betterComponentWidth() {
    switch (WindowUtil.uiType) {
      case UIType.Column_1: {
        return this.realWidth
      }
      case UIType.Column_2: {
        return (this.realWidth-10)/2
      }
      case UIType.Column_3: {
        return (this.realWidth-20)/3
      }
      default: {
        return 0
      }
    }
  }
  @Builder
  ipv4() {
    IPv4({config: this.config, comp_width: this.betterComponentWidth})
      .geometryTransition("ipv4")
  }
  @Builder
  hostname() {
    Hostname({config: this.config, comp_width: this.betterComponentWidth})
      .geometryTransition("hostname")
  }
  @Builder
  profiles() {
    FlexItems({
      type: "profile",
      config: this.config,
      comp_width: this.betterComponentWidth,
      items: Manager.network_identities as SafeLightWeightSet<itemType>,
      clickCallback: (item) => {
        if (this.config.network_identity.toString() != (item as network_identity).toString()) {
          this.config.network_identity.from(item as network_identity)
        }
        Manager.network_identities.forEach((value) => {
          Logger.debug("all profiles: "+value)
        })
      },
      selectedFunc: (item) => {
        return this.config.network_identity.toString() == (item as network_identity).toString()
      }
    })
      .geometryTransition("profiles")
  }
  @Builder
  peers() {
    FlexItems({
      type: "peer",
      config: this.config,
      comp_width: this.betterComponentWidth,
      items: Manager.peers as SafeLightWeightSet<itemType>,
      clickCallback: (item) => {
        if (this.config.peer.has(item as peer)) {
          this.config.peer.delete(item as peer)
        }else {
          this.config.peer.add(item as peer)
        }
      },
      selectedFunc: (item) => {
        return this.config.peer.has(item as peer)
      }
    })
      .geometryTransition("peers")
  }
  @Builder
  flags() {
    Flags({config: this.config, comp_width: this.betterComponentWidth})
      .geometryTransition("flags")
  }
  @Builder
  cidrs() {
    FlexItems({
      type: "cidr",
      config: this.config,
      comp_width: this.betterComponentWidth,
      items: Manager.cidrs as SafeLightWeightSet<itemType>,
      clickCallback: (item) => {
        if (this.config.proxy_network.has(item as cidr)) {
          this.config.proxy_network.delete(item as cidr)
        }else {
          this.config.proxy_network.add(item as cidr)
        }
      },
      selectedFunc: (item) => {
        return this.config.proxy_network.has(item as cidr)
      }
    })
      .geometryTransition("cidrs")
  }
  @Builder
  listeners() {
    FlexItems({
      type: "listener",
      config: this.config,
      comp_width: this.betterComponentWidth,
      items: Manager.listeners as SafeLightWeightSet<itemType>,
      clickCallback: (item) => {
        if (this.config.listeners.has(item as listener)) {
          this.config.listeners.delete(item as listener)
        }else {
          this.config.listeners.add(item as listener)
        }
      },
      selectedFunc: (item) => {
        return this.config.listeners.has(item as listener)
      }
    })
      .geometryTransition("listeners")
  }
  @Builder
  wl() {
    FlexItems({
      type: "whitelist",
      config: this.config,
      comp_width: this.betterComponentWidth,
      items: Manager.whitelist as SafeLightWeightSet<itemType>,
      clickCallback: (item) => {
        if (this.config.flags.relay_network_whitelist.whitelist.has(item as WrappedString)) {
          this.config.flags.relay_network_whitelist.whitelist.delete(item as WrappedString)
        }else {
          this.config.flags.relay_network_whitelist.whitelist.add(item as WrappedString)
        }
      },
      selectedFunc: (item) => {
        return this.config.flags.relay_network_whitelist.whitelist.has(item as WrappedString)
      }
    })
      .geometryTransition("wl")
  }
  @Builder
  routes() {
    FlexItems({
      type: "route",
      config: this.config,
      comp_width: this.betterComponentWidth,
      items: Manager.routes as SafeLightWeightSet<itemType>,
      clickCallback: (item) => {
        if (this.config.routes.has(item as route)) {
          this.config.routes.delete(item as route)
        }else {
          this.config.routes.add(item as route)
        }
      },
      selectedFunc: (item) => {
        return this.config.routes.has(item as route)
      }
    })
      .geometryTransition("routes")
  }
  @Builder
  exit_nodes() {
    FlexItems({
      type: "exit_node",
      config: this.config,
      comp_width: this.betterComponentWidth,
      items: Manager.exit_nodes as SafeLightWeightSet<itemType>,
      clickCallback: (item) => {
        if (this.config.exit_nodes.has(item as exit_node)) {
          this.config.exit_nodes.delete(item as exit_node)
        }else {
          this.config.exit_nodes.add(item as exit_node)
        }
      },
      selectedFunc: (item) => {
        return this.config.exit_nodes.has(item as exit_node)
      }
    })
      .geometryTransition("exit_nodes")
  }
  @Builder
  wg() {
    WGPortal({config: this.config, comp_width: this.betterComponentWidth})
  }
  @Builder
  socks5() {
    Socks5({config: this.config, comp_width: this.betterComponentWidth})
  }
  @Builder
  basicText() {
    Text("基础设置")
      .width('100%')
      .fontSize(12)
      .fontColor($r("sys.color.font_secondary"))
      .margin({left: 10, bottom: 5})
  }
  @Builder
  advancedText() {
    Text("高级设置")
      .width('100%')
      .fontSize(12)
      .fontColor($r("sys.color.font_secondary"))
      .margin({left: 10, bottom: 5})
  }
  @Builder
  basic() {
    Column({space: 10}) {
      this.basicText()
      this.ipv4()
      this.hostname()
      this.profiles()
      this.peers()
    }
    .width('100%')
    .margin({bottom: 10})
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.START, SafeAreaEdge.BOTTOM])
  }
  @Builder
  advanced() {
    Column({space: 10}) {
      this.advancedText()
      this.flags()
      if (WindowUtil.uiType != UIType.Column_3) {
        this.cidrs()
        this.listeners()
        this.wl()
        this.routes()
        this.exit_nodes()
      }
      this.wg()
      this.socks5()
    }
    .width('100%')
    .margin({bottom: 10})
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.START, SafeAreaEdge.BOTTOM])
  }
  @Builder
  moreItems() {
    Column({space: 10}) {
      Text(" ")
        .fontSize(12)
        .fontColor($r("sys.color.font_secondary"))
        .margin({left: 10, bottom: 5})
      this.cidrs()
      this.listeners()
      this.wl()
      this.routes()
      this.exit_nodes()
    }
    .width('100%')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.START, SafeAreaEdge.BOTTOM])
  }

  build() {
    Scroll() {
      Column() {
        if (WindowUtil.uiType == UIType.Column_1) {
          this.basic()
          this.advanced()
        }else {
          Row({space: 10}) {
            Row() {
              this.basic()
            }
            .layoutWeight(33)
            Row() {
              this.advanced()
            }
            .layoutWeight(33)
            if (WindowUtil.uiType == UIType.Column_3) {
              Row() {
                this.moreItems()
              }
              .layoutWeight(33)
            }
          }
          .width('100%')
          .alignItems(VerticalAlign.Top)
          .justifyContent(FlexAlign.SpaceEvenly)
        }
        Blank()
          .height(WindowUtil.height*0.1)
          .width('100%')
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.START, SafeAreaEdge.BOTTOM])
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.START, SafeAreaEdge.BOTTOM])
    }
    .scrollBar(BarState.Off)
    .width('100%')
    .height(this.comp_height)
    .align(Alignment.Top)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.START, SafeAreaEdge.BOTTOM])
    .edgeEffect(EdgeEffect.Spring)
    .onAreaChange((a,b) => {
      this.realWidth = b.width as number
    })
  }
}