import { HMRouter, HMRouterMgr } from '@hadss/hmrouter'
import { HdsNavigation, HdsNavigationTitleMode, hdsMaterial, TitleBarStyleOptions } from '@kit.UIDesignKit'
import { LengthMetrics } from '@kit.ArkUI'
import { deviceInfo } from '@kit.BasicServicesKit'
import { HdsMenuButton } from '../Components'
import { RemoteStatusPageParam } from '../../types/navigation/PageParam'
import { RemoteManageService } from '../../services/remote/RemoteManageService'
import {
  RuntimeInstanceState,
  RuntimePeerConnInfo,
  RuntimePeerInfo,
  RuntimeRouteView
} from '../../types/runtime/RuntimeTypes'
import { sendToast } from '../../ToastUtil'

function remoteStatusTitleStyle(): TitleBarStyleOptions {
  if (deviceInfo.distributionOSApiVersion >= 60100 && hdsMaterial.getSystemMaterialTypes().length > 0) {
    return {
      scrollEffectOpts: {
        enableScrollEffect: true,
        scrollEffectType: deviceInfo.sdkApiVersion >= 23 ? 3 : 2,
        blurEffectiveStartOffset: LengthMetrics.vp(0),
        blurEffectiveEndOffset: LengthMetrics.vp(20),
      },
      originalStyle: {
        contentStyle: {
          titleStyle: {
            mainTitleColor: $r('sys.color.font_primary'),
            subTitleColor: $r('sys.color.font_secondary')
          },
          menuStyle: {
            iconColor: $r('sys.color.font_primary')
          },
          backIconStyle: {
            iconColor: $r('sys.color.font_primary')
          }
        }
      },
      systemMaterialEffect: {
        materialType: hdsMaterial.MaterialType.ADAPTIVE,
        materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
      }
    }
  }
  return {
    scrollEffectOpts: {
      enableScrollEffect: true,
      scrollEffectType: deviceInfo.sdkApiVersion >= 23 ? 3 : 2,
      blurEffectiveStartOffset: LengthMetrics.vp(0),
      blurEffectiveEndOffset: LengthMetrics.vp(20),
    },
    originalStyle: {
      contentStyle: {
        titleStyle: {
          mainTitleColor: $r('sys.color.font_primary'),
          subTitleColor: $r('sys.color.font_secondary')
        },
        menuStyle: {
          iconColor: $r('sys.color.font_primary'),
          backgroundColor: $r('sys.color.background_primary')
        },
        backIconStyle: {
          iconColor: $r('sys.color.font_primary'),
          backgroundColor: $r('sys.color.background_primary')
        }
      }
    }
  }
}

function boolState(value: boolean): string {
  return value ? '开启' : '关闭'
}

function natState(value: number | string | undefined): string {
  if (value === undefined || value === null) {
    return 'Unknown'
  }
  return `${value}`
}

function formatBytes(bytes: number): string {
  if (bytes < 1024) {
    return `${bytes.toFixed(0)} B`
  }
  if (bytes < 1024 * 1024) {
    return `${(bytes / 1024).toFixed(1)} KB`
  }
  if (bytes < 1024 * 1024 * 1024) {
    return `${(bytes / 1024 / 1024).toFixed(1)} MB`
  }
  return `${(bytes / 1024 / 1024 / 1024).toFixed(1)} GB`
}

function formatLatency(latencyUs: number | undefined): string {
  if (latencyUs === undefined || latencyUs < 0 || latencyUs > 9999999999) {
    return 'N/A'
  }
  return `${(latencyUs / 1000).toFixed(0)} ms`
}

@Builder
function remoteStatusHeader(title: string) {
  Text(title)
    .width('100%')
    .fontSize(14)
    .fontColor($r('sys.color.font_secondary'))
    .padding({ top: 10, left: 5, bottom: 3 })
}

@Builder
function remoteStatusPill(text: string, active: boolean = false) {
  Text(text)
    .fontSize(12)
    .fontColor(active ? $r('sys.color.brand_font') : $r('sys.color.font_secondary'))
    .padding({ left: 8, right: 8, top: 4, bottom: 4 })
    .borderRadius(10)
    .backgroundColor(active ? $r('sys.color.brand') : $r('sys.color.comp_background_secondary'))
}

@Builder
function remoteStatusValueRow(title: string, value: string) {
  Row() {
    Text(title)
      .fontSize(14)
      .fontColor($r('sys.color.font_secondary'))
    Blank()
    Text(value)
      .fontSize(15)
      .fontColor($r('sys.color.font_primary'))
      .maxLines(1)
      .textOverflow({ overflow: TextOverflow.Ellipsis })
  }
  .width('100%')
}

@Extend(Column)
function remoteStatusCardStyle() {
  .width('100%')
  .borderRadius(18)
  .backgroundColor($r('sys.color.comp_background_primary'))
  .shadow({
    radius: 7,
    color: '#1F000000'
  })
  .padding(12)
}

@HMRouter({ pageUrl: 'RemoteStatusPage' })
@ComponentV2
export struct RemoteStatusPage {
  @Local configId: string = ''
  @Local title: string = '远端状态'
  @Local remoteSessionId: string = ''
  @Local remoteDeviceName: string = ''
  @Local instance: RuntimeInstanceState | undefined = undefined
  private refreshTimer: number = -1

  aboutToAppear(): void {
    const param = HMRouterMgr.getCurrentParam() as RemoteStatusPageParam
    this.configId = param.configId
    this.title = param.title || this.configId
    this.remoteSessionId = param.remoteSessionId ?? RemoteManageService.currentSessionKey ?? ''
    this.remoteDeviceName = param.remoteDeviceName ?? RemoteManageService.currentDeviceName
    if (!RemoteManageService.isCurrentSession(this.remoteSessionId)) {
      sendToast('远端连接已变化，请重新进入状态页', $r('sys.symbol.exclamationmark_circle'), 1)
      setTimeout(() => {
        HMRouterMgr.pop()
      }, 0)
      return
    }
    this.refresh()
    this.startRefreshTimer()
  }

  aboutToDisappear(): void {
    this.stopRefreshTimer()
  }

  private startRefreshTimer(): void {
    if (this.refreshTimer >= 0) {
      return
    }
    this.refreshTimer = setInterval(() => {
      if (RemoteManageService.isCurrentSession(this.remoteSessionId)) {
        this.refresh(true)
      }
    }, 3000)
  }

  private stopRefreshTimer(): void {
    if (this.refreshTimer < 0) {
      return
    }
    clearInterval(this.refreshTimer)
    this.refreshTimer = -1
  }

  private async refresh(silent: boolean = false): Promise<void> {
    if (!RemoteManageService.isCurrentSession(this.remoteSessionId)) {
      if (!silent) {
        sendToast('远端未连接', $r('sys.symbol.exclamationmark_circle'), 1)
      }
      return
    }
    try {
      this.instance = await RemoteManageService.getRuntimeInstance(this.configId, this.remoteSessionId)
      if (!this.instance && !silent) {
        sendToast('远端配置未运行', $r('sys.symbol.exclamationmark_circle'), 1)
      }
    } catch (error) {
      if (!silent) {
        sendToast(`刷新远端状态失败：${(error as Error).message}`, $r('sys.symbol.exclamationmark_circle'), 1)
      }
    }
  }

  private peerTraffic(peer: RuntimePeerInfo): number {
    let bytes = 0
    const conns = peer.conns ?? []
    conns.forEach((conn: RuntimePeerConnInfo) => {
      bytes += conn.stats?.rxBytes ?? 0
      bytes += conn.stats?.txBytes ?? 0
    })
    return bytes
  }

  private peerLatency(peer: RuntimePeerInfo): string {
    let latency: number | undefined = undefined
    const conns = peer.conns ?? []
    conns.forEach((conn: RuntimePeerConnInfo) => {
      if (conn.stats?.latencyUs !== undefined) {
        latency = latency === undefined ? conn.stats.latencyUs : Math.min(latency, conn.stats.latencyUs)
      }
    })
    return formatLatency(latency)
  }

  @Builder
  private overviewCard(instance: RuntimeInstanceState) {
    ListItem() {
      Column({ space: 10 }) {
        Row({ space: 8 }) {
          remoteStatusPill(instance.running ? '运行中' : '已停止', instance.running)
          remoteStatusPill(`Peer ${instance.peers?.length ?? 0}`)
          remoteStatusPill(`Route ${instance.routes?.length ?? 0}`)
        }
        .width('100%')
        remoteStatusValueRow('虚拟 IPv4', instance.myNodeInfo?.virtualIpv4Cidr ??
          instance.myNodeInfo?.virtualIpv4 ?? '未分配')
        remoteStatusValueRow('TUN', `${instance.tunRequired ? '需要' : '不需要'} / ${instance.tunAttached ? '已附加' : '未附加'}`)
        remoteStatusValueRow('Magic DNS', boolState(instance.magicDnsEnabled))
        remoteStatusValueRow('出口节点', instance.needExitNode ? '需要' : '不需要')
        remoteStatusValueRow('UDP NAT', natState(instance.myNodeInfo?.udpNatType))
        remoteStatusValueRow('TCP NAT', natState(instance.myNodeInfo?.tcpNatType))
      }
      .remoteStatusCardStyle()
    }
    .margin({ bottom: 10 })
  }

  @Builder
  private routeCard(route: RuntimeRouteView) {
    ListItem() {
      Column({ space: 6 }) {
        Row() {
          Text(route.hostname ?? `Peer ${route.peerId}`)
            .fontSize(15)
            .fontColor($r('sys.color.font_primary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Blank()
          remoteStatusPill(route.cost === 1 ? 'P2P' : `Cost ${route.cost ?? 0}`, route.cost === 1)
        }
        .width('100%')
        Text(route.ipv4Cidr ?? route.ipv4 ?? route.ipv6Cidr ?? '无地址')
          .fontSize(12)
          .fontColor($r('sys.color.font_secondary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text((route.proxyCidrs ?? []).join(', ') || '无代理网段')
          .fontSize(12)
          .fontColor($r('sys.color.font_secondary'))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .remoteStatusCardStyle()
    }
    .margin({ bottom: 10 })
  }

  @Builder
  private peerCard(peer: RuntimePeerInfo) {
    ListItem() {
      Column({ space: 8 }) {
        Row() {
          Text(`Peer ${peer.peerId}`)
            .fontSize(15)
            .fontColor($r('sys.color.font_primary'))
          Blank()
          Text(this.peerLatency(peer))
            .fontSize(12)
            .fontColor($r('sys.color.font_secondary'))
        }
        .width('100%')
        Text(`连接 ${peer.conns?.length ?? 0} · 流量 ${formatBytes(this.peerTraffic(peer))}`)
          .fontSize(12)
          .fontColor($r('sys.color.font_secondary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        ForEach(peer.conns ?? [], (conn: RuntimePeerConnInfo) => {
          Column({ space: 3 }) {
            Text(conn.tunnelType ?? conn.connId ?? 'unknown')
              .fontSize(12)
              .fontColor($r('sys.color.font_primary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            Text(conn.resolvedRemoteAddr ?? conn.remoteAddr ?? conn.localAddr ?? '')
              .fontSize(11)
              .fontColor($r('sys.color.font_secondary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .padding({ top: 5 })
          .border({
            width: { top: 1 },
            color: { top: $r('sys.color.comp_divider') }
          })
        }, (conn: RuntimePeerConnInfo, index: number) => conn.connId ?? `${peer.peerId}-${index}`)
      }
      .remoteStatusCardStyle()
    }
    .margin({ bottom: 10 })
  }

  build() {
    HdsNavigation() {
      List() {
        ListItem()
          .height(64)
        if (this.instance) {
          ListItemGroup({ header: remoteStatusHeader('概览') }) {
            this.overviewCard(this.instance!)
          }
          ListItemGroup({ header: remoteStatusHeader('路由') }) {
            if ((this.instance!.routes?.length ?? 0) === 0) {
              ListItem() {
                Column() {
                  Text('暂无路由')
                    .fontSize(16)
                    .fontColor($r('sys.color.font_secondary'))
                }
                .alignItems(HorizontalAlign.Center)
                .remoteStatusCardStyle()
              }
              .margin({ bottom: 10 })
            } else {
              ForEach(this.instance!.routes ?? [], (route: RuntimeRouteView) => {
                this.routeCard(route)
              }, (route: RuntimeRouteView) => `${route.peerId}-${route.ipv4Cidr ?? route.ipv4 ?? route.ipv6Cidr ?? ''}`)
            }
          }
          ListItemGroup({ header: remoteStatusHeader('节点') }) {
            if ((this.instance!.peers?.length ?? 0) === 0) {
              ListItem() {
                Column() {
                  Text('暂无节点')
                    .fontSize(16)
                    .fontColor($r('sys.color.font_secondary'))
                }
                .alignItems(HorizontalAlign.Center)
                .remoteStatusCardStyle()
              }
              .margin({ bottom: 10 })
            } else {
              ForEach(this.instance!.peers ?? [], (peer: RuntimePeerInfo) => {
                this.peerCard(peer)
              }, (peer: RuntimePeerInfo) => `${peer.peerId}`)
            }
          }
        } else {
          ListItem() {
            Column({ space: 10 }) {
              SymbolGlyph($r('sys.symbol.exclamationmark_circle'))
                .fontSize(28)
                .fontColor([$r('sys.color.font_secondary')])
              Text('远端配置未运行或状态暂不可用')
                .fontSize(16)
                .fontColor($r('sys.color.font_secondary'))
            }
            .height(180)
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Center)
            .remoteStatusCardStyle()
          }
          .margin({ bottom: 10 })
        }
        ListItem()
          .height(120)
      }
      .width('100%')
      .height('100%')
      .padding({ left: 15, right: 15 })
      .scrollBar(BarState.Auto)
    }
    .titleBar({
      style: remoteStatusTitleStyle(),
      content: {
        title: {
          mainTitle: this.title,
          subTitle: this.remoteDeviceName
        },
        menu: {
          value: [HdsMenuButton('刷新', $r('sys.symbol.arrow_2_circlepath'), () => this.refresh())]
        }
      }
    })
    .mode(NavigationMode.Stack)
    .titleMode(HdsNavigationTitleMode.MINI)
    .hideBackButton(false)
    .hideTitleBar(false)
    .backgroundColor($r('sys.color.background_secondary'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
