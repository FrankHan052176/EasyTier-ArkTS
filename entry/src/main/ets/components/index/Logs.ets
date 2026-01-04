import { AppManager } from '../../AppManager'
import { logColor } from '../../util/Conversion'
import { LightModifier } from '../../class/modifier/SymbolLight'
import { StackLightModifier } from '../../class/modifier/BackgroundLight'

@ComponentV2
export struct Logs {
  @Local showSheet: boolean = false
  @Local tab_index: number = 0
  @Local lightMod: LightModifier = new LightModifier($r('sys.color.font_primary'))
  @Local bgMode: StackLightModifier = new StackLightModifier()

  @Computed
  get w(): number {
    return AppManager.layout.getCompSize('Logs').lane_w
  }

  @Computed
  get h(): number {
    return AppManager.layout.getCompSize('Logs').lane_h
  }

  @Computed
  get appCount(): number {
    return AppManager.easytier.appLogs.size
  }

  @Computed
  get netCount(): number {
    return AppManager.easytier.nmLogs.size
  }

  @Computed
  get ohCount(): number {
    return AppManager.easytier.ohLogs.size
  }

  @Computed
  get totalCount(): number {
    return this.appCount + this.netCount + this.ohCount
  }

  @Computed
  get latestLog(): string {
    // 简单的获取最后一条日志的逻辑，优先显示App日志，其次网络
    if (this.appCount > 0) {
      return Array.from(AppManager.easytier.appLogs)[this.appCount - 1]
    }
    if (this.netCount > 0) {
      return Array.from(AppManager.easytier.nmLogs)[this.netCount - 1]
    }
    if (this.ohCount > 0) {
      return Array.from(AppManager.easytier.ohLogs)[this.ohCount - 1]
    }
    return "暂无日志数据"
  }

  @Builder
  LogSheetContent() {
    Column() {
      Tabs({ barPosition: BarPosition.Start, index: this.tab_index }) {
        TabContent() {
          this.LogList(Array.from(AppManager.easytier.appLogs.values()))
        }.tabBar("App日志")

        TabContent() {
          this.LogList(Array.from(AppManager.easytier.nmLogs.values()))
        }.tabBar("网络日志")

        TabContent() {
          this.LogList(Array.from(AppManager.easytier.ohLogs.values()))
        }.tabBar("ArkUI日志")
      }
      .barMode(BarMode.Fixed)
      .width('100%')
      .layoutWeight(1)
      .animationDuration(300)
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  LogList(list: Array<string>) {
    List() {
      if (list.length > 0) {
        ForEach(list, (msg: string) => {
          ListItem() {
            Text(msg.substring(1))
              .fontSize(12)
              .fontColor(logColor(msg))
              .fontFamily('Monospace')
              .width('100%')
              .copyOption(CopyOptions.LocalDevice)
              .padding({ top: 2, bottom: 2 })
          }
        })
      } else {
        ListItem() {
          Column() {
            SymbolGlyph($r('sys.symbol.doc_plaintext_and_checkmark'))
              .fontSize(48)
              .fontColor([$r('sys.color.font_secondary')])
            Text("暂无日志")
              .fontSize(14)
              .fontColor($r('sys.color.font_secondary'))
              .margin({ top: 8 })
          }
          .width("100%")
          .height(200)
          .justifyContent(FlexAlign.Center)
        }
      }
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Auto)
    .alignListItem(ListItemAlign.Start)
    .padding({
      left: 16,
      right: 16,
      top: 8,
      bottom: 8
    })
  }

  @Builder
  point() {
    Column()
      .size({ width: 1, height: 1 })
      .attributeModifier(this.lightMod)
  }

  @Builder
  Logo() {
    SymbolGlyph($r('sys.symbol.list_bullet_square'))
      .fontSize(24)
      .fontColor([$r('sys.color.font_primary')])
      .overlay(this.point, {
        align: Alignment.Center
      })
  }

  @Builder
  Size1x1() {
    Column() {
      Row() {
        this.Logo()
      }
      .width('100%')
      .justifyContent(FlexAlign.Start)

      Column() {
        Text(this.totalCount.toString())
          .fontSize(32)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('sys.color.font_primary'))
        Text("日志总数")
          .fontSize(12)
          .fontColor($r('sys.color.font_secondary'))
      }
      .layoutWeight(1)
      .justifyContent(FlexAlign.Center)
    }
    .padding(16)
    .width('100%')
    .height('100%')
  }

  // --- 2x1 布局 ---
  @Builder
  Size2x1() {
    Column() {
      Row() {
        this.Logo()
      }
      .width('100%')
      .justifyContent(FlexAlign.Start)
      .margin({ bottom: 8 })

      Row() {
        Column() {
          Text(this.totalCount.toString())
            .fontSize(36)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('sys.color.font_primary'))

          Text("日志总数")
            .fontSize(12)
            .fontColor($r('sys.color.font_secondary'))
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)

        Row({ space: 16 }) {
          this.MiniStatItem($r('sys.symbol.house'), 0)
          this.MiniStatItem($r('sys.symbol.wifi'), 1)
          this.MiniStatItem($r('sys.symbol.HarmonyOS'), 2)
        }
      }
      .width('100%')
      .layoutWeight(1)
      .justifyContent(FlexAlign.SpaceBetween)
      .alignItems(VerticalAlign.Center)
    }
    .padding(16)
    .width('100%')
    .height('100%')
  }

  @Builder
  MiniStatItem(icon: Resource, tabIdx: number) {
    Column({ space: 4 }) {
      SymbolGlyph(icon)
        .fontSize(20)
        .fontColor([$r('sys.color.font_secondary')])
      Text((tabIdx === 0 ? this.appCount : (tabIdx === 1 ? this.netCount : this.ohCount)).toString())
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('sys.color.font_primary'))
    }
    .onClick(() => {
      this.tab_index = tabIdx
      this.showSheet = true
    })
  }

  // --- 1x2 布局 ---
  @Builder
  Size1x2() {
    Column() {
      Row() {
        this.Logo()
      }
      .width('100%')
      .justifyContent(FlexAlign.Start)
      .margin({ bottom: 8 })

      Column({ space: 8 }) {
        this.ListStatItem("App", this.appCount, $r('sys.symbol.house'), 0)
        this.ListStatItem("网络", this.netCount, $r('sys.symbol.wifi'), 1)
        this.ListStatItem("系统", this.ohCount, $r('sys.symbol.HarmonyOS'), 2)
      }
      .justifyContent(FlexAlign.Center)
      .height('100%')
    }
    .padding(16)
    .width('100%')
    .height('100%')
  }

  @Builder
  ListStatItem(name: string, count: number, icon: Resource, tabIdx: number) {
    Row() {
      Row({ space: 8 }) {
        SymbolGlyph(icon)
          .fontSize(18)
          .fontColor([$r('sys.color.font_secondary')])
        Text(name)
          .fontSize(14)
          .fontColor($r('sys.color.font_primary'))
      }

      Text(count.toString())
        .fontSize(14)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('sys.color.font_primary'))
    }
    .width('100%')
    .justifyContent(FlexAlign.SpaceBetween)
    .padding(8)
    .backgroundColor($r('sys.color.comp_background_tertiary'))
    .borderRadius(8)
    .onClick(() => {
      this.tab_index = tabIdx
      this.showSheet = true
    })
  }

  // --- 2x2 布局 ---
  @Builder
  Size2x2() {
    Column() {
      Row() {
        this.Logo()

        Blank()

        Text("Total: " + this.totalCount)
          .fontSize(14)
          .fontColor($r('sys.color.font_secondary'))
      }
      .width('100%')
      .margin({ bottom: 12 })

      Row({ space: 8 }) {
        this.CardStatItem("App日志", $r('sys.symbol.house'), 0)
        this.CardStatItem("网络日志", $r('sys.symbol.wifi'), 1)
        this.CardStatItem("ArkUI", $r('sys.symbol.HarmonyOS'), 2)
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceBetween)
      .margin({ bottom: 12 })

      Column() {
        Text("最新日志")
          .fontSize(12)
          .fontColor($r('sys.color.font_secondary'))
          .margin({ bottom: 4 })
        Text(this.latestLog.substring(1)) // 去掉颜色标记
          .fontSize(12)
          .fontColor($r('sys.color.font_primary'))
          .fontFamily('Monospace')
          .maxLines(5)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .padding(8)
          .backgroundColor($r('sys.color.comp_background_tertiary'))
          .borderRadius(8)
          .width('100%')
          .layoutWeight(1)
          .align(Alignment.TopStart)
      }
      .width('100%')
      .layoutWeight(1)
    }
    .padding(16)
    .width('100%')
    .height('100%')
  }

  @Builder
  CardStatItem(name: string, icon: Resource, tabIdx: number) {
    Column() {
      SymbolGlyph(icon)
        .fontSize(24)
        .fontColor([$r('sys.color.interactive_active')])
        .margin({ bottom: 4 })
      Text((tabIdx === 0 ? this.appCount : (tabIdx === 1 ? this.netCount : this.ohCount)).toString())
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('sys.color.font_primary'))
      Text(name)
        .fontSize(12)
        .fontColor($r('sys.color.font_secondary'))
    }
    .layoutWeight(1)
    .height(90)
    .justifyContent(FlexAlign.Center)
    .backgroundColor($r('sys.color.comp_background_tertiary'))
    .borderRadius(12)
    .onClick(() => {
      this.tab_index = tabIdx
      this.showSheet = true
    })
  }

  build() {
    Stack() {
      // 适配不同尺寸
      if (this.w === 1 && this.h === 1) {
        this.Size1x1()
      } else if (this.w === 2 && this.h === 1) {
        this.Size2x1()
      } else if (this.w === 1 && this.h === 2) {
        this.Size1x2()
      } else {
        this.Size2x2()
      }
    }
    .width('100%')
    .height('100%')
    .onClick(() => {
      this.showSheet = true
    })
    .bindSheet($$this.showSheet, this.LogSheetContent(), {
      height: SheetSize.LARGE,
      preferType: SheetType.CENTER,
      showClose: true,
      dragBar: true,
      title: { title: "日志中心" },
      blurStyle: BlurStyle.Thin
    })
    .attributeModifier(this.bgMode)
  }
}