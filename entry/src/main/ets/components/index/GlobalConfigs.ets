import { CompTitle } from './Basic'

@Builder
function Global_Content(symbol: Resource, name: string | Resource, sizeFunc: () => number) {
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

@Extend(Column)
function comp_bg() {
  .width('100%')
  .height('100%')
  .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
}

@Builder
export function GlobalConfigs() {
  Column() {
    CompTitle("全局配置", $r("sys.color.font_primary"), ()=>{return -1}, $r("app.string.i18_ge"))
    List({space: 5}) {
      Global_Content($r('sys.symbol.worldclock'),"Peers",()=>{return 0})
      Global_Content($r('sys.symbol.position'),"监听地址",()=>{return 0})
      Global_Content($r('sys.symbol.list_bullet'),"自定义路由",()=>{return 0})
      Global_Content($r('sys.symbol.list_bullet'),"子网代理",()=>{return 0})
      Global_Content($r('sys.symbol.local_fill'),"出口节点",()=>{return 0})
      Global_Content($r('sys.symbol.person'),"网络白名单",()=>{return 0})
    }
    .scrollBar(BarState.Off)
    .hitTestBehavior(HitTestMode.Block)
    .width('100%')
    .height('100%')
    .layoutWeight(100)
    .padding({left: 5, right: 5, top: 5})
    .borderRadius(18)
  }
  .comp_bg()
}