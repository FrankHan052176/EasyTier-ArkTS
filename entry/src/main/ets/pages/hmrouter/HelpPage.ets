import { HMRouter, HMRouterMgr } from "@hadss/hmrouter";
import { flagsSymbol } from "../../util/FlagsInfo";
import { LengthMetrics } from "@kit.ArkUI";
import { hdsEffect } from "@kit.UIDesignKit";
import { WindowUtil } from "../../WindowUtil";
import { lane } from "../../util/Conversion";
import { Logger } from "../../util/Logger";
import { DesktopLayout } from "desktop_layout";

@HMRouter({ pageUrl: "HelpPage" })
@ComponentV2
export struct HelpPage {
  @Local currentIndex: number = 10
  private controller: SwiperController = new SwiperController()
  private totalSteps: number = 9

  isStepActive(start: number, index: number): boolean {
    const end = this.currentIndex + WindowUtil.uiType / 2
    Logger.debug(""+index+","+start+","+end)
    return index >= start && index < end;
  }

  aboutToAppear(): void {
    setTimeout(() => {
      this.currentIndex = 0
    }, 50)
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      // Background
      Column()
        .width('100%')
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
        .height('100%')
        .backgroundColor($r("sys.color.background_secondary"))

      Column() {
        Row() {
          Text(`教程 ${this.currentIndex + 1}/${this.totalSteps + 1 - WindowUtil.uiType / 2}`)
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor($r("sys.color.font_secondary"))
            .animation({ duration: 300 })
          
          Blank() 
          
          Text("跳过")
            .fontSize(14)
            .fontColor($r("sys.color.font_tertiary"))
            .onClick(() => {
              HMRouterMgr.pop()
            })
            .visibility(this.currentIndex+1 == (this.totalSteps + 1 - WindowUtil.uiType / 2) ? Visibility.Hidden : Visibility.Visible)
        }
        .width('100%')
        .padding({ top: 12, left: 24, right: 24 })
        .height(56)

        // Main Content Swiper
        Swiper(this.controller) {
          Step1_Intro({ isActive: this.isStepActive(this.currentIndex, 0) })
          Step1_New({ isActive: this.isStepActive(this.currentIndex, 1) })
          Step2_Operation_Add({ isActive: this.isStepActive(this.currentIndex, 2) })
          Step2_Operation_Manage({ isActive: this.isStepActive(this.currentIndex, 3) })
          Step3_Identity({ isActive: this.isStepActive(this.currentIndex, 4) })
          Step4_Connection({ isActive: this.isStepActive(this.currentIndex, 5) })
          Step5_ProtocolFlags({ isActive: this.isStepActive(this.currentIndex, 6) })
          Step6_FeatureFlags({ isActive: this.isStepActive(this.currentIndex, 7) })
          Step7_Advanced({ isActive: this.isStepActive(this.currentIndex, 8) })
        }
        .loop(false)
        .indicator(false)
        .onChange((index: number) => {
          animateToImmediately({ duration: 400, curve: Curve.FastOutSlowIn }, () => {
            this.currentIndex = index
          })
        })
        .width('100%')
        .height('100%')
        .displayCount(WindowUtil.uiType / 2)
        .itemSpace(24)
        .prevMargin(WindowUtil.uiType / 2 > 1 ? 24 : 0)
        .nextMargin(WindowUtil.uiType / 2 > 1 ? 24 : 0)
      }
      .width('100%')
      .height('100%')

      // Bottom Navigation Area
      Column() {
        // Primary Action Button
        Button(this.currentIndex+1 == (this.totalSteps + 1 - WindowUtil.uiType / 2) ? "开始使用" : "下一步")
          .type(ButtonType.Capsule)
          .width('85%')
          .height(48)
          .backgroundColor($r("sys.color.brand"))
          .fontColor(Color.White)
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .onClick(() => {
            if (this.currentIndex+1 < (this.totalSteps + 1 - WindowUtil.uiType / 2)) {
              this.controller.showNext()
            } else {
              HMRouterMgr.pop()
            }
          })
          .shadow(ShadowStyle.OUTER_DEFAULT_MD)
          .animation({ duration: 300 }) // Smooth text transition
      }
      .padding({ bottom: 16 })
      .width(lane(2))
      .backgroundColor(Color.Transparent)
    }
    .width('100%')
    .height('100%')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}

// --- Step 1: Welcome & Intro ---

@ComponentV2
struct Step1_Intro {
  @Param isActive: boolean = false
  @Local showContent: boolean = false
  @Local controller: hdsEffect.ShaderEffectController = new hdsEffect.ShaderEffectController();

  @Monitor("isActive")
  onActiveChange() {
    this.showContent = this.isActive
  }

  aboutToAppear() {
    // Initial check without animation to prevent flash, or use delay
    if (this.isActive) {
      setTimeout(() => { this.showContent = true }, 50)
    }
  }

  build() {
    Column() {
      Column() {
        Image($r('app.media.easytier_256'))
          .width(128)
          .height(128)
          .autoResize(true)
          .scale({ x: this.showContent ? 1 : 0.5, y: this.showContent ? 1 : 0.5 })
          .opacity(this.showContent ? 1 : 0)
          .animation({ duration: 600, curve: Curve.EaseOut, delay: 100 })
      }
      .height('30%')
      .justifyContent(FlexAlign.Center)

      Row() {
        Text("EasyTier")
          .fontSize(48)
          .fontWeight(FontWeight.Bolder)
          .fontColor($r("sys.color.font_primary"))
          .blendMode(BlendMode.DST_IN, BlendApplyType.OFFSCREEN)
      }
      .linearGradient({
        direction: GradientDirection.Right,
        colors: [
          ['rgba(255,200,50,1)', 0.0],
          ['rgba(0,230,118,1)', 1.0],
        ]
      })
      .blendMode(BlendMode.SRC_OVER, BlendApplyType.OFFSCREEN)
      .translate({ y: this.showContent ? 0 : 20 })
      .animation({ duration: 500, delay: 200, curve: Curve.FastOutSlowIn })
      .opacity(this.showContent ? 1 : 0)
      
      Text("简易且强大的组网工具")
        .fontSize(18)
        .fontColor($r("sys.color.font_secondary"))
        .margin({ top: 12 })
        .opacity(this.showContent ? 1 : 0)
        .translate({ y: this.showContent ? 0 : 20 })
        .animation({ duration: 500, delay: 300, curve: Curve.FastOutSlowIn })

      Text("无需繁琐配置，轻松连接您的所有设备。\n支持点对点直连，安全、高效、私密。" )
        .fontSize(15)
        .textAlign(TextAlign.Center)
        .fontColor($r("sys.color.font_tertiary"))
        .margin({ top: 32, left: 32, right: 32 })
        .lineHeight(24)
        .opacity(this.showContent ? 1 : 0)
        .translate({ y: this.showContent ? 0 : 20 })
        .animation({ duration: 500, delay: 400, curve: Curve.FastOutSlowIn })
    }
    .width('100%')
    .height('100%')
    .padding({ top: 60 })
  }
}

@Builder
function exampleComp(type: string) {
  Column() {
    Text(type)
  }
  .width('100%')
  .height('100%')
  .borderRadius(18)
  .backgroundColor($r("sys.color.comp_background_primary"))
  .justifyContent(FlexAlign.Center)
}

@ComponentV2
struct Step1_New {
  @Param isActive: boolean = false
  @Local showContent: boolean = false

  @Monitor("isActive")
  onActiveChange() {
    this.showContent = this.isActive
  }

  build() {
    Column() {
      TitleSection({ title: "新版本特性", subtitle: "又加了什么好玩的呢?", show: this.showContent })

      // Card Visualization
      Column() {
        DesktopLayout({
          comp_sequence: [{
            type: "全新UI风格",
            x: 0,
            y: 0,
            width: 1,
            height: 1
          },{
            type: "自定义桌面",
            x: 0,
            y: 1,
            width: 1,
            height: 1
          },{
            type: "长按我，试试看",
            x: 1,
            y: 0,
            width: 1,
            height: 1
          }],
          types: ["全新UI风格", "自定义桌面", "长按我，试试看"],
          contentBuilder: wrapBuilder(exampleComp),
          name: "test",
          breakpoints: [
            { breakpoint: 0, columns: 2 },
          ],
          maxCompW: 2,
          maxCompH: 2
        })
          .width('100%')
          .height('100%')
      }
      .width('100%')
      .opacity(this.showContent ? 1 : 0)
      .scale({ x: this.showContent ? 1 : 0.9, y: this.showContent ? 1 : 0.9 })
      .animation({ duration: 600, curve: Curve.Friction, delay: 200 })
      .margin({ top: 20, bottom: 40 })

      // Feature List
      Scroll() {
        Column({ space: 16 }) {
          FeatureItem({
            icon: $r("sys.symbol.plus"),
            title: "添加实例",
            desc: "通过点击首页左上角加号新建实例\n支持导入剪切板中的配置",
            delay: 400,
            show: this.showContent
          })
          FeatureItem({
            icon: $r("sys.symbol.rectangle_and_arrowshape_turn_up_right_fill"),
            title: "接收分享",
            desc: "接收其他鸿蒙设备分享的实例",
            delay: 500,
            show: this.showContent
          })
          FeatureItem({
            icon: $r("sys.symbol.file_preview"),
            title: "文件导入",
            desc: "通过文件分享导入 Toml 配置",
            delay: 600,
            show: this.showContent
          })
          Column().height(100)
        }
        .width('100%')
      }
      .width('85%')
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
  }
}

// --- Step 2: Dashboard Operation (Add) ---

@ComponentV2
struct Step2_Operation_Add {
  @Param isActive: boolean = false
  @Local showContent: boolean = false

  @Monitor("isActive")
  onActiveChange() {
    this.showContent = this.isActive
  }

  build() {
    Column() {
      TitleSection({ title: "操作指南", subtitle: "如何添加您的网络实例", show: this.showContent })

      // Card Visualization
      Column() {
        InstanceCardMock()
      }
      .width('90%')
      .opacity(this.showContent ? 1 : 0)
      .scale({ x: this.showContent ? 1 : 0.9, y: this.showContent ? 1 : 0.9 })
      .animation({ duration: 600, curve: Curve.Friction, delay: 200 })
      .margin({ top: 20, bottom: 40 })

      // Feature List
      Scroll() {
        Column({ space: 16 }) {
          FeatureItem({
            icon: $r("sys.symbol.plus"),
            title: "添加实例",
            desc: "通过点击首页左上角加号新建实例\n支持导入剪切板中的配置",
            delay: 400,
            show: this.showContent
          })
          FeatureItem({
            icon: $r("sys.symbol.rectangle_and_arrowshape_turn_up_right_fill"),
            title: "接收分享",
            desc: "接收其他鸿蒙设备分享的实例",
            delay: 500,
            show: this.showContent
          })
          FeatureItem({
            icon: $r("sys.symbol.file_preview"),
            title: "文件导入",
            desc: "通过文件分享导入 Toml 配置",
            delay: 600,
            show: this.showContent
          })
          Column().height(100)
        }
        .width('100%')
      }
      .width('85%')
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
  }
}

// --- Step 2: Dashboard Operation (Manage) ---

@ComponentV2
struct Step2_Operation_Manage {
  @Param isActive: boolean = false
  @Local showContent: boolean = false

  @Monitor("isActive")
  onActiveChange() {
    this.showContent = this.isActive
  }

  build() {
    Column() {
      TitleSection({ title: "管理实例", subtitle: "连接与配置网络", show: this.showContent })

      // Card Visualization
      Column() {
        InstanceCardMock()
      }
      .width('90%')
      .opacity(this.showContent ? 1 : 0)
      .scale({ x: this.showContent ? 1 : 0.9, y: this.showContent ? 1 : 0.9 })
      .animation({ duration: 600, curve: Curve.Friction, delay: 200 })
      .margin({ top: 20, bottom: 40 })

      // Feature List
      Scroll() {
        Column({ space: 16 }) {
          FeatureItem({
            icon: $r("sys.symbol.key_shield"),
            title: "选中实例",
            desc: "点击卡片左侧区域选中当前网络",
            delay: 400,
            show: this.showContent
          })
          FeatureItem({
            icon: $r("sys.symbol.square_and_pencil"),
            title: "编辑配置",
            desc: "点击右侧图标修改详细参数",
            delay: 500,
            show: this.showContent
          })
          FeatureItem({
            icon: $r("sys.symbol.play_circle"),
            title: "一键启动",
            desc: "选中后点击底部按钮即可连接",
            delay: 600,
            show: this.showContent
          })
          Column().height(100)
        }
        .width('100%')
      }
      .width('85%')
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
  }
}

// --- Step 3: Identity Setup ---

@ComponentV2
struct Step3_Identity {
  @Param isActive: boolean = false
  @Local showContent: boolean = false

  @Monitor("isActive")
  onActiveChange() {
    this.showContent = this.isActive
  }

  build() {
    Column() {
      TitleSection({ title: "身份配置", subtitle: "加入组网的核心凭证", show: this.showContent })

      List() {
        ListItem() {
          CollapsibleSection({
            title: "身份信息 (Identity)",
            icon: $r("sys.symbol.person_shield_fill"),
            content: "包含网络名称 (Network Name) 和网络密钥 (Secret)。\n\n这是加入组网的唯一凭证，所有希望互通的节点必须使用完全相同的名称和密钥。",
            delay: 200,
            show: this.showContent,
            defaultOpen: true
          })
        }
        .padding({ left: 20, right: 20 })
      }
      .fadingEdge(true, {
        fadingEdgeLength: LengthMetrics.vp(16)
      })
      .layoutWeight(1)
      .width('100%')
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
  }
}

// --- Step 4: Network Connectivity ---

@ComponentV2
struct Step4_Connection {
  @Param isActive: boolean = false
  @Local showContent: boolean = false

  @Monitor("isActive")
  onActiveChange() {
    this.showContent = this.isActive
  }

  build() {
    Column() {
      TitleSection({ title: "网络连接", subtitle: "配置节点 IP 与对等连接", show: this.showContent })

      List() {
        ListItem() {
          CollapsibleSection({
            title: "虚拟IP (Virtual IP)",
            icon: $r("sys.symbol.person_line_turn_down_right_person"),
            content: "配置节点在组网内的虚拟 IP 地址。\n\n建议手动指定（如 10.0.0.1）以便记忆和管理，若开启 DHCP 则会自动获取。",
            delay: 200,
            show: this.showContent,
            defaultOpen: true
          })
        }
        .padding({ left: 20, right: 20, bottom: 12 })

        ListItem() {
          CollapsibleSection({
            title: "对等节点 (Peers)",
            icon: $r("sys.symbol.share"),
            content: "添加公共节点或已知节点的 URL (tcp://...)\n\n至少需要连接一个公共节点进行打洞（NAT穿透），或者直接连接到其他已知 IP 的节点。",
            delay: 300,
            show: this.showContent,
            defaultOpen: true
          })
        }
        .padding({ left: 20, right: 20 })
      }
      .fadingEdge(true, {
        fadingEdgeLength: LengthMetrics.vp(16)
      })
      .layoutWeight(1)
      .width('100%')
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
  }
}

// --- Step 5: Protocol & Performance Flags ---

@ComponentV2
struct Step5_ProtocolFlags {
  @Param isActive: boolean = false
  @Local showContent: boolean = false

  @Monitor("isActive")
  onActiveChange() {
    this.showContent = this.isActive
  }

  build() {
    Column() {
      TitleSection({ title: "协议与性能", subtitle: "优化传输协议与延迟", show: this.showContent })

      List() {
        ListItem() { CollapsibleSection({ title: $r('app.string.latency_first'), icon: flagsSymbol("latency_first"), content: $r('app.string.latency_first_help'), delay: 100, show: this.showContent }) }.padding({ left: 20, right: 20, bottom: 12 })
        ListItem() { CollapsibleSection({ title: $r('app.string.use_smoltcp'), icon: flagsSymbol("use_smoltcp"), content: $r('app.string.use_smoltcp_help'), delay: 150, show: this.showContent }) }.padding({ left: 20, right: 20, bottom: 12 })
        ListItem() { CollapsibleSection({ title: $r('app.string.multi_thread'), icon: flagsSymbol("multi_thread"), content: $r('app.string.multi_thread_help'), delay: 200, show: this.showContent }) }.padding({ left: 20, right: 20, bottom: 12 })
        ListItem() { CollapsibleSection({ title: $r('app.string.enable_kcp_proxy'), icon: flagsSymbol("enable_kcp_proxy"), content: $r('app.string.enable_kcp_proxy_help'), delay: 250, show: this.showContent }) }.padding({ left: 20, right: 20, bottom: 12 })
        ListItem() { CollapsibleSection({ title: $r('app.string.disable_kcp_input'), icon: flagsSymbol("disable_kcp_input"), content: $r('app.string.disable_kcp_input_help'), delay: 300, show: this.showContent }) }.padding({ left: 20, right: 20, bottom: 12 })
        ListItem() { CollapsibleSection({ title: $r('app.string.enable_quic_proxy'), icon: flagsSymbol("enable_quic_proxy"), content: $r('app.string.enable_quic_proxy_help'), delay: 350, show: this.showContent }) }.padding({ left: 20, right: 20, bottom: 12 })
        ListItem() { CollapsibleSection({ title: $r('app.string.disable_quic_input'), icon: flagsSymbol("disable_quic_input"), content: $r('app.string.disable_quic_input_help'), delay: 400, show: this.showContent }) }.padding({ left: 20, right: 20, bottom: 12 })
        ListItem() { CollapsibleSection({ title: $r('app.string.disable_tcp_hole_punching'), icon: flagsSymbol("disable_tcp_hole_punching"), content: $r('app.string.disable_tcp_hole_punching_help'), delay: 450, show: this.showContent }) }.padding({ left: 20, right: 20, bottom: 12 })
        ListItem() { CollapsibleSection({ title: $r('app.string.disable_udp_hole_punching'), icon: flagsSymbol("disable_udp_hole_punching"), content: $r('app.string.disable_udp_hole_punching_help'), delay: 500, show: this.showContent }) }.padding({ left: 20, right: 20, bottom: 12 })
        ListItem() { CollapsibleSection({ title: $r('app.string.disable_sym_hole_punching'), icon: flagsSymbol("disable_sym_hole_punching"), content: $r('app.string.disable_sym_hole_punching_help'), delay: 550, show: this.showContent }) }.padding({ left: 20, right: 20, bottom: 12 })

        ListItem().height(100)
      }
      .fadingEdge(true, {
        fadingEdgeLength: LengthMetrics.vp(16)
      })
      .layoutWeight(1)
      .width('100%')
      .scrollBar(BarState.Off)
      .margin({bottom: WindowUtil.navigationBarHeight})
    }
    .width('100%')
    .height('100%')
  }
}

// --- Step 6: Features & Security Flags ---

@ComponentV2
struct Step6_FeatureFlags {
  @Param isActive: boolean = false
  @Local showContent: boolean = false

  @Monitor("isActive")
  onActiveChange() {
    this.showContent = this.isActive
  }

  build() {
    Column() {
      TitleSection({ title: "功能与安全", subtitle: "管理网络行为与隐私设置", show: this.showContent })

      List() {
        ListItem() { CollapsibleSection({ title: $r('app.string.disable_p2p'), icon: flagsSymbol("disable_p2p"), content: $r('app.string.disable_p2p_help'), delay: 100, show: this.showContent }) }.padding({ left: 20, right: 20, bottom: 12 })
        ListItem() { CollapsibleSection({ title: $r('app.string.p2p_only'), icon: flagsSymbol("p2p_only"), content: $r('app.string.p2p_only_help'), delay: 150, show: this.showContent }) }.padding({ left: 20, right: 20, bottom: 12 })
        ListItem() { CollapsibleSection({ title: $r('app.string.no_tun'), icon: flagsSymbol("no_tun"), content: $r('app.string.no_tun_help'), delay: 200, show: this.showContent }) }.padding({ left: 20, right: 20, bottom: 12 })
        ListItem() { CollapsibleSection({ title: $r('app.string.enable_exit_node'), icon: flagsSymbol("enable_exit_node"), content: $r('app.string.enable_exit_node_help'), delay: 250, show: this.showContent }) }.padding({ left: 20, right: 20, bottom: 12 })
        ListItem() { CollapsibleSection({ title: $r('app.string.relay_all_peer_rpc'), icon: flagsSymbol("relay_all_peer_rpc"), content: $r('app.string.relay_all_peer_rpc_help'), delay: 350, show: this.showContent }) }.padding({ left: 20, right: 20, bottom: 12 })
        ListItem() { CollapsibleSection({ title: $r('app.string.proxy_forward_by_system'), icon: flagsSymbol("proxy_forward_by_system"), content: $r('app.string.proxy_forward_by_system_help'), delay: 400, show: this.showContent }) }.padding({ left: 20, right: 20, bottom: 12 })
        ListItem() { CollapsibleSection({ title: $r('app.string.disable_encryption'), icon: flagsSymbol("disable_encryption"), content: $r('app.string.disable_encryption_help'), delay: 450, show: this.showContent }) }.padding({ left: 20, right: 20, bottom: 12 })
        ListItem() { CollapsibleSection({ title: $r('app.string.enable_magic_dns'), icon: flagsSymbol("enable_magic_dns"), content: $r('app.string.enable_magic_dns_help'), delay: 500, show: this.showContent }) }.padding({ left: 20, right: 20, bottom: 12 })
        ListItem() { CollapsibleSection({ title: $r('app.string.enable_private_mode'), icon: flagsSymbol("enable_private_mode"), content: $r('app.string.enable_private_mode_help'), delay: 550, show: this.showContent }) }.padding({ left: 20, right: 20, bottom: 12 })

        ListItem().height(100)
      }
      .fadingEdge(true, {
        fadingEdgeLength: LengthMetrics.vp(16)
      })
      .layoutWeight(1)
      .width('100%')
      .scrollBar(BarState.Off)
      .margin({bottom: WindowUtil.navigationBarHeight})
    }
    .width('100%')
    .height('100%')
  }
}

// --- Step 7: Advanced Routing ---

@ComponentV2
struct Step7_Advanced {
  @Param isActive: boolean = false
  @Local showContent: boolean = false

  @Monitor("isActive")
  onActiveChange() {
    this.showContent = this.isActive
  }

  build() {
    Column() {
      TitleSection({ title: "高级路由", subtitle: "代理转发与端口映射", show: this.showContent })

      List() {
        ListItem() {
          CollapsibleSection({
            title: "子网代理 (Proxy Networks)",
            icon: $r("sys.symbol.arrow_triangle_merge"),
            content: "配置通过本节点代理访问的子网段 (CIDR)。\n\n开启后，组网内的其他节点可以访问本节点所在的局域网设备。",
            delay: 100,
            show: this.showContent
          })
        }.padding({ left: 20, right: 20, bottom: 12 })
        ListItem() {
          CollapsibleSection({
            title: "端口映射 (Port Mapping)",
            icon: $r("sys.symbol.arrow_bounce_right"),
            content: "将虚拟 IP 的端口流量转发到本地物理端口。\n\n实现内网穿透，让外部通过虚拟 IP 访问本地服务。",
            delay: 200,
            show: this.showContent
          })
        }.padding({ left: 20, right: 20, bottom: 12 })
        ListItem() {
          CollapsibleSection({
            title: "监听地址 (Listeners)",
            icon: $r("sys.symbol.dot_radiowaves_left_and_right"),
            content: "自定义节点监听的协议和端口 (如 tcp://0.0.0.0:11010)。\n\n用于固定服务端口，方便防火墙配置或外部直连。",
            delay: 300,
            show: this.showContent,
            defaultOpen: true
          })
        }.padding({ left: 20, right: 20, bottom: 12 })
        ListItem() {
          CollapsibleSection({
            title: "Socks5 代理",
            icon: $r("sys.symbol.lock_fill"),
            content: "开启内置 Socks5 服务器。\n\n可以将组网变成一个安全代理通道，实现流量转发。",
            delay: 400,
            show: this.showContent
          })
        }.padding({ left: 20, right: 20, bottom: 12 })
        ListItem() {
          CollapsibleSection({
            title: "VPN Portal",
            icon: $r("sys.symbol.lock_fill"),
            content: "开启内置 WG 服务器。\n\n可以使用 WG 接入虚拟网。",
            delay: 400,
            show: this.showContent
          })
        }.padding({ left: 20, right: 20, bottom: 12 })

        ListItem().height(100)
      }
      .fadingEdge(true, {
        fadingEdgeLength: LengthMetrics.vp(16)
      })
      .layoutWeight(1)
      .width('100%')
      .scrollBar(BarState.Off)
      .margin({bottom: WindowUtil.navigationBarHeight})
    }
    .width('100%')
    .height('100%')
  }
}

// --- Shared Components ---

@ComponentV2
struct TitleSection {
  @Param title: string = ""
  @Param subtitle: string = ""
  @Param show: boolean = false

  build() {
    Column() {
      Text(this.title)
        .fontSize(28)
        .fontWeight(FontWeight.Bold)
        .fontColor($r("sys.color.font_primary"))
        .opacity(this.show ? 1 : 0)
        .translate({ y: this.show ? 0 : -20 })
        .animation({ duration: 500, curve: Curve.FastOutSlowIn })
      
      Text(this.subtitle)
        .fontSize(14)
        .fontColor($r("sys.color.font_secondary"))
        .margin({ top: 8 })
        .opacity(this.show ? 1 : 0)
        .translate({ y: this.show ? 0 : -20 })
        .animation({ duration: 500, delay: 100, curve: Curve.FastOutSlowIn })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ top: 40, left: 24, right: 24, bottom: 32 })
  }
}

@ComponentV2
struct CollapsibleSection {
  @Param title: ResourceStr = ""
  @Param icon: Resource = $r('sys.symbol.gearshape')
  @Param content: ResourceStr = ""
  @Param delay: number = 0
  @Param show: boolean = false
  @Param defaultOpen: boolean = false
  @Local isOpen: boolean = this.defaultOpen

  build() {
    Column() {
      Row() {
        Row() {
          SymbolGlyph(this.icon)
            .fontSize(20)
            .fontColor([$r("sys.color.brand")])
            .margin({ right: 12 })
          Text(this.title)
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor($r("sys.color.font_primary"))
            .layoutWeight(1)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .layoutWeight(1)

        SymbolGlyph($r("sys.symbol.chevron_down"))
          .fontSize(16)
          .fontColor([$r("sys.color.font_tertiary")])
          .rotate({ angle: this.isOpen ? 180 : 0 })
          .animation({ duration: 300 })
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceBetween)
      .padding(16)

      if (this.isOpen) {
        Column() {
          Text(this.content)
            .fontSize(14)
            .fontColor($r("sys.color.font_secondary"))
            .lineHeight(20)
        }
        .width('100%')
        .padding({ left: 16, right: 16, bottom: 16, top: 4 })
        .transition(TransitionEffect.scale({x: 1.0, y: 0, centerY: 0}).animation({ duration: 300 }))
      }
    }
    .backgroundColor($r("sys.color.comp_background_primary"))
    .width('100%')
    .opacity(this.show ? 1 : 0)
    .translate({ y: this.show ? 0 : 30 })
    .borderRadius(12)
    .animation({ duration: 500, delay: this.delay, curve: Curve.FastOutSlowIn })
    .onClick(() => {
      animateTo({ duration: 300, curve: Curve.FastOutSlowIn }, () => {
        this.isOpen = !this.isOpen
      })
    })
  }
}

@ComponentV2
struct FeatureItem {
  @Param icon: Resource = $r("sys.symbol.circle")
  @Param title: string = ""
  @Param desc: string = ""
  @Param delay: number = 0
  @Param show: boolean = false

  build() {
    Row() {
      SymbolGlyph(this.icon)
        .fontSize(24)
        .fontColor([$r("sys.color.brand")])
        .margin({ right: 16 })
      
      Column() {
        Text(this.title)
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor($r("sys.color.font_primary"))
        Text(this.desc)
          .fontSize(14)
          .fontColor($r("sys.color.font_secondary"))
          .margin({ top: 4 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
    }
    .width('100%')
    .padding(16)
    .backgroundColor($r("sys.color.comp_background_primary"))
    .borderRadius(12)
    .opacity(this.show ? 1 : 0)
    .translate({ x: this.show ? 0 : 50 })
    .animation({ duration: 500, delay: this.delay, curve: Curve.FastOutSlowIn })
  }
}

@ComponentV2
struct InstanceCardMock {
  build() {
    Column() {
      // Header
      Row() {
        SymbolGlyph($r('sys.symbol.key_shield'))
          .fontSize(24)
          .fontColor([$r('sys.color.brand')])
        Blank()
        Text("1") 
          .fontSize(14)
          .fontColor($r('sys.color.font_secondary'))
      }
      .width('100%')
      .margin({ bottom: 12 })

      // Content
      Row() {
        Column() {
           Text("My Network")
             .fontSize(18)
             .fontWeight(FontWeight.Bold)
             .fontColor($r("sys.color.brand"))
           Text("Instance ID")
             .fontSize(14)
             .fontColor($r("sys.color.font_tertiary"))
             .margin({ top: 4 })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Row({ space: 12 }) {
          // Mock Buttons
          MockButton($r("sys.symbol.star"))
          MockButton($r("sys.symbol.square_and_pencil"))
        }
      }
    }
    .padding(16)
    .width('100%')
    .height(130)
    .backgroundColor($r("sys.color.comp_background_primary"))
    .borderRadius(18)
    .shadow(ShadowStyle.OUTER_DEFAULT_MD)
  }
}

@Builder
function MockButton(icon: Resource) {
  Column() {
    SymbolGlyph(icon)
      .fontSize(22)
      .fontColor([$r("sys.color.font_primary")])
  }
  .width(44)
  .height(44)
  .justifyContent(FlexAlign.Center)
  .backgroundColor($r('sys.color.comp_background_tertiary'))
  .borderRadius(12)
}
