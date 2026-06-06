import { AppManager } from '../../AppManager'
import { logColor } from '../../util/Conversion'
import { LightModifier } from '../../class/modifier/SymbolLight'
import { StackLightModifier } from '../../class/modifier/BackgroundLight'
import { LogDataSource } from '../../class/data_source/LogDataSource'
import { hdsEffect, hdsMaterial, HdsNavigation, HdsNavigationTitleMode,
  IconStyleMode,
  TitleBarStyleOptions } from '@kit.UIDesignKit'
import { deviceInfo } from '@kit.BasicServicesKit'
import { LengthMetrics } from '@kit.ArkUI'

@ComponentV2
export struct Logs {
  @Local showSheet: boolean = false
  @Local tab_index: number = 0
  @Local lightMod: LightModifier = new LightModifier($r('sys.color.font_primary'))
  @Local bgMode: StackLightModifier = new StackLightModifier()
  @Consumer("w") w: number = 1
  @Consumer("h") h: number = 1

  @Computed
  get appCount(): number {
    return AppManager.easytier.appLogs.totalCount()
  }

  @Computed
  get totalCount(): number {
    return this.appCount
  }

  @Computed
  get latestLog(): string {
    if (this.appCount > 0) {
      return AppManager.easytier.appLogs.getData(this.appCount - 1)
    }
    return "暂无日志数据"
  }

  navTitleStyle(): TitleBarStyleOptions {
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
              mainTitleColor: $r("sys.color.font_primary"),
              subTitleColor: $r("sys.color.font_secondary")
            },
            menuStyle: {
              iconColor: $r("sys.color.font_primary")
            },
            backIconStyle: {
              iconColor: $r("sys.color.font_primary")
            }
          }
        },
        systemMaterialEffect: {
          materialType: hdsMaterial.MaterialType.ADAPTIVE,
          materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
        }
      }
    }else {
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
              mainTitleColor: $r("sys.color.font_primary"),
              subTitleColor: $r("sys.color.font_secondary")
            },
            menuStyle: {
              iconColor: $r("sys.color.font_primary"),
              backgroundColor: $r("sys.color.background_primary")
            },
            backIconStyle: {
              iconColor: $r("sys.color.font_primary"),
              backgroundColor: $r("sys.color.background_primary")
            }
          }
        }
      }
    }
  }

  @Builder
  LogSheetContent() {
    HdsNavigation() {
      Column() {
        Tabs({ barPosition: BarPosition.Start, index: this.tab_index }) {
          TabContent() {
            this.LogList(AppManager.easytier.appLogs)
          }.tabBar("运行日志")
        }
        .barMode(BarMode.Fixed)
        .width('100%')
        .layoutWeight(1)
        .animationDuration(300)
      }
      .width('100%')
      .height('100%')
    }
    .height('100%')
    .width('100%')
    .titleBar({
      style: this.navTitleStyle(),
      content: {
        title: {
          mainTitle: "日志中心"
        },
        menu: {
          value: [{
            content: {
              icon: $r('sys.symbol.xmark'),
              type: IconStyleMode.NORMAL,
              action: () => {
                this.showSheet = false;
              },
            }
          }]
        },

      },
      enableComponentSafeArea: true
    })
    .mode(NavigationMode.Stack)
    .titleMode(HdsNavigationTitleMode.MODAL)
    .hideBackButton(true)
    .hideTitleBar(false)
    .height('100%')
    .width('100%')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  @Builder
  LogList(list: LogDataSource) {
    List() {
      if (list.totalCount() > 0) {
        LazyForEach(list, (msg: string) => {
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
      .onClick(() => {
        this.showSheet = true
      })
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
        .onClick(() => {
          this.showSheet = true
        })

        Row({ space: 16 }) {
          this.MiniStatItem($r('sys.symbol.house'), 0)
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
      Text(this.appCount.toString())
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
        this.ListStatItem("运行日志", this.appCount, $r('sys.symbol.house'), 0)
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
        this.CardStatItem("运行日志", $r('sys.symbol.house'), 0)
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
      Text(this.appCount.toString())
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
    .borderRadius(18)
    .bindSheet($$this.showSheet, this.LogSheetContent(), {
      height: SheetSize.LARGE,
      preferType: SheetType.CENTER,
      showClose: false,
      dragBar: false
    })
    .attributeModifier(this.bgMode)
    .backgroundColor($r("sys.color.comp_background_primary"))
    .shadow({
      radius: 7,
      color: '#1F000000'
    })
    .visualEffect(new hdsEffect.HdsEffectBuilder().pointLight({
      illuminatedType: hdsEffect.PointLightIlluminatedType.BORDER_CONTENT,
    }).buildEffect())
  }
}
