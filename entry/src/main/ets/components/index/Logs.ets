import { logColor } from '../../util/Conversion'
import { CompTitle } from './Basic'
import {
  SegmentButtonV2Items, TabSegmentButtonV2
} from '@kit.ArkUI'
import { deviceInfo } from '@kit.BasicServicesKit'
import { AppManager } from '../../AppManager'

@Extend(Column)
function comp_bg() {
  .width('100%')
  .height('100%')
  .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
}

const items: string[] = [
  'App日志',
  '网络日志',
  'ArkUI日志'
];

@Builder
function LogList(list: Array<string>) {
  List() {
    if (list.length > 0) {
      ForEach(list, (msg: string) => {
        ListItem() {
          TextArea({
            text: msg.substring(1)
          })
            .fontSize(14)
            .fontColor(logColor(msg))
            .backgroundColor(Color.Transparent)
            .padding(0)
            .borderRadius(0)
            .focusable(false)
        }
      })
      ListItem()
        .height(100)
        .width('100%')
    } else {
      ListItem() {
        Text("无日志")
          .fontSize(14)
          .width("100%")
      }
    }
  }
  .scrollBar(BarState.Off)
  .alignListItem(ListItemAlign.Start)
  .padding({ left: 10, right: 10 })
  .clip(true)
  .borderRadius(18)
  .height("100%")
  .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.START, SafeAreaEdge.BOTTOM])
}

@ComponentV2
export struct Logs {
  @Local log: boolean = false
  @Local log_index: number = 0
  @Local real_index: number = 0
  @Local controller: SwiperController = new SwiperController()

  @Builder
  logSheet() {
    Column() {
      if (deviceInfo.sdkApiVersion >= 18) {
        TabSegmentButtonV2({
          items: new SegmentButtonV2Items([
            { text: 'App日志' },
            { text: '网络日志' },
            { text: 'ArkUI日志' }
          ]),
          selectedIndex: this.real_index!!,
          onItemClicked: (index) => {
            this.controller.changeIndex(index, true)
          }
        })
          .width('80%')
          .margin({ bottom: 10 })
      } else {
        Row() {
          ForEach(items, (item: string, index: number) => {
            Button(item, { type: ButtonType.Capsule, stateEffect: this.real_index === index })
              .backgroundColor(0x317aff)
              .width(90)
              .opacity(this.real_index === index ? 1 : 0.4)
              .onClick(() => {
                animateToImmediately({
                  duration: 300,
                  curve: Curve.Ease
                }, () => {
                  this.real_index = index
                })
                this.controller.changeIndex(index, true)
              })
          })
        }
        .alignItems(VerticalAlign.Center)
        .justifyContent(FlexAlign.SpaceAround)
        .width('100%')
      }
      Swiper(this.controller) {
        LogList(Array.from(AppManager.easytier.appLogs.values()))
        LogList(Array.from(AppManager.easytier.nmLogs.values()))
        LogList(Array.from(AppManager.easytier.ohLogs.values()))
      }
      .index($$this.log_index)
      .layoutWeight(100)
      .disableSwipe(true)
      .indicator(false)
    }
    .width('100%')
    .height('100%')
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
        .margin({ right: 5 })

        Text(name)
          .fontColor($r("sys.color.font_primary"))
      }

      Row() {
        Text("" + sizeFunc()).fontSize(14).fontColor($r("sys.color.font_primary"))
        Text($r("app.string.i18_tiao")).fontSize(10).fontColor($r("sys.color.font_primary"))
      }
      .alignItems(VerticalAlign.Bottom)
    }
    .width('100%')
    .alignItems(VerticalAlign.Bottom)
    .justifyContent(FlexAlign.SpaceBetween)
    .onClick(() => {
      this.log_index = index
      this.real_index = index
      this.log = true
    })
  }

  build() {
    Column() {
      CompTitle("日志", $r("sys.color.font_primary"), () => {
        return AppManager.easytier.appLogs.size + AppManager.easytier.nmLogs.size + AppManager.easytier.ohLogs.size
      }, $r("app.string.i18_tiao"))
      Column({ space: 10 }) {
        this.LogShower($r("sys.symbol.house"), "App日志", () => {
          return AppManager.easytier.appLogs.size
        }, 0)
        this.LogShower($r("sys.symbol.wifi"), "网络日志", () => {
          return AppManager.easytier.nmLogs.size
        }, 1)
        this.LogShower($r("sys.symbol.HarmonyOS"), "ArkUI日志", () => {
          return AppManager.easytier.ohLogs.size
        }, 2)
      }
      .justifyContent(FlexAlign.SpaceAround)
      .width('100%')
      .layoutWeight(100)
      .padding(10)
    }
    .comp_bg()
    .bindSheet($$this.log, this.logSheet(), {
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
}