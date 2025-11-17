import { itemType } from "../pages/content/FlexItems"
import { cidr, exit_node, listener, network_identity, peer, Protocol, route, WrappedString } from "./ETConfig"
import { LengthMetrics } from "@kit.ArkUI"

let protocols = [Protocol.TCP, Protocol.UDP, Protocol.QUIC, Protocol.WS, Protocol.WSS, Protocol.WG]
@Extend(Text)
function tips() {
  .width('100%')
  .fontSize(14)
  .fontColor($r("sys.color.font_secondary"))
  .textAlign(TextAlign.Center)
}
@Extend(TextInput)
function underline(textAlign: TextAlign = TextAlign.Center) {
  .padding({left: 1, right: 1, top: 5, bottom: 5})
  .backgroundColor(Color.Transparent)
  .border({
    width: {
      start: LengthMetrics.vp(0),
      end: LengthMetrics.vp(0),
      top: LengthMetrics.vp(0),
      bottom: LengthMetrics.vp(1)
    },
    color: {
      bottom: $r("sys.color.comp_divider")
    },
    radius: {
      bottomStart: LengthMetrics.vp(0),
      bottomEnd: LengthMetrics.vp(0)
    },
    style: {
      bottom: BorderStyle.Solid
    }
  })
  .textAlign(textAlign)
}

@Builder
export function ItemEditSheet(item:itemType) {
  if (item instanceof peer) {
    PeerAndListenerSheet(item)
  }else if (item instanceof network_identity) {
    ProfileSheet(item)
  }else if (item instanceof cidr) {
    CidrAndRouteSheet(item)
  }else if (item instanceof listener) {
    PeerAndListenerSheet(item)
  }else if (item instanceof WrappedString) {
    WhiteListSheet(item)
  }else if (item instanceof route) {
    CidrAndRouteSheet(item)
  }else if (item instanceof exit_node) {
    ExitNodeSheet(item)
  }
}

@Builder
export function PeerAndListenerSheet(item:peer | listener) {
  Column() {
    Row() {
      TextPicker({ range: protocols, selected: protocols.indexOf(item._protocol)})
        .onChange((_value: string | string[], index: number | number[]) => {
          item._protocol = protocols[index as number]
        })
        .canLoop(false)
        .defaultPickerItemHeight(36)
        .width(70)
      Text("://")
        .fontSize(18)
        .margin({left: 2, right: 2})
      TextInput({text: item._domain})
        .underline()
        .width(150)
        .onChange((value: string) => {
          item._domain = value
        })
      Text(":")
        .fontSize(18)
        .margin({left: 2, right: 2})
      TextInput({text: ""+item._port})
        .underline()
        .width(60)
        .maxLength(5)
        .type(InputType.Number)
        .onChange((value: string) => {
          item._port = Number.parseInt(value)
        })
    }
    .width('100%')
    Text(`
协议、域名、端口请分别设置
      `)
      .tips()
    Blank()
      .width('100%')
      .height(100)
  }
  .width('90%')
}
@Builder
export function ProfileSheet(profile:network_identity) {
  Column() {
    Row() {
      Text("名称")
        .align(Alignment.Start)
        .fontSize(14)
        .fontColor($r("sys.color.font_secondary"))
        .margin({right:10})
      TextInput({ text: profile.network_name})
        .underline(TextAlign.Start)
        .layoutWeight(100)
        .type(InputType.USER_NAME)
        .onChange((value) => {
          profile.network_name = value
        })
    }
    .margin({bottom:10})
    .alignItems(VerticalAlign.Center)
    .justifyContent(FlexAlign.Start)
    .width('100%')
    Row() {
      Text("密码")
        .align(Alignment.Start)
        .fontSize(14)
        .fontColor($r("sys.color.font_secondary"))
        .margin({right:10})
      TextInput({ text: profile.network_secret})
        .underline(TextAlign.Start)
        .layoutWeight(100)
        .type(InputType.Password)
        .onChange((value) => {
          profile.network_secret = value
        })
    }
    .margin({bottom:20})
    .alignItems(VerticalAlign.Center)
    .justifyContent(FlexAlign.Start)
    .width('100%')
    Text(`
凭证分为名称与密码，等同于网络名称与网络密码
      `)
      .tips()
    Blank()
      .width('100%')
      .height(100)
  }
  .width('90%')
}
@Builder
export function CidrAndRouteSheet(item:cidr | route) {
  Column() {
    Row() {
      TextInput({text: item.ipv4})
        .underline()
        .width(70)
        .onChange((value: string) => {
          item.ipv4 = value
        })
      Text("/")
        .fontSize(18)
        .margin({left: 2, right: 2})
      TextInput({text: ""+item.mask})
        .underline()
        .maxLength(2)
        .width(30)
        .onChange((value: string) => {
          item.mask = Number.parseInt(value)
        })
    }
    .width('100%')
    .justifyContent(FlexAlign.Center)
    Text(`
请设置网段，如10.0.0.0/24
      `)
      .tips()
    Blank()
      .width('100%')
      .height(100)
  }
  .width('90%')
}
@Builder
export function WhiteListSheet(item: WrappedString) {
  Column() {
    Row() {
      TextInput()
        .underline()
        .width('80%')
        .onChange((value: string) => {
          item.from(value)
        })
    }
    .width('100%')
    .justifyContent(FlexAlign.Center)
    Text(`
请设置网络名
      `)
      .tips()
    Blank()
      .width('100%')
      .height(100)
  }
  .width('90%')
}
@Builder
export function ExitNodeSheet(item: exit_node) {
  Column() {
    Row() {
      TextInput({text: item.ipv4})
        .underline()
        .width("90%")
        .onChange((value: string) => {
          item.ipv4 = value
        })
    }
    .width('100%')
    .justifyContent(FlexAlign.Center)
    Text(`
请设置虚拟IP，如10.0.0.2
      `)
      .width('100%')
      .fontSize(14)
      .fontColor($r("sys.color.font_secondary"))
      .textAlign(TextAlign.Center)
    Blank()
      .width('100%')
      .height(100)
  }
  .width('90%')
}