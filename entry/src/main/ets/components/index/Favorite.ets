import { AppManager } from '../../AppManager'
import { sendToast } from '../../ToastUtil'

@ComponentV2
export struct Favorite {
  @Local trigger: number = 0

  @Computed
  get w(): number {
    return AppManager.layout.getCompSize('Favorite').lane_w
  }

  @Computed
  get h(): number {
    return AppManager.layout.getCompSize('Favorite').lane_h
  }

  @Computed
  get isRunning(): boolean {
    return AppManager.easytier.isFavoritesRunning()
  }

  @Computed
  get favoriteUuid(): string | undefined {
    return AppManager.data.favorite
  }

  @Computed
  get favoriteName(): string {
    return this.favoriteUuid ? AppManager.data.configUUIDNameMap.get(this.favoriteUuid) ?? "Unknown" : "无收藏"
  }

  readonly brandColor: string = 'rgba(255,200,50,1)'

  toggle() {
    if (!this.favoriteUuid) {
      return
    }

    if (this.isRunning) {
      AppManager.easytier.stop()
    } else {
      if (AppManager.easytier.runningNetworks.size > 0) {
        AppManager.easytier.stop()
      }
      if (!AppManager.easytier.start(this.favoriteUuid)) {
        sendToast("Amazing! 收藏的实例不存在", $r("sys.symbol.exclamationmark_circle"), 1)
      }
    }
    if (this.trigger === 0) {
      this.trigger = 1
    }
  }

  @Builder
  EmptyView(iconSize: number, fontSize: number) {
    Column() {
      SymbolGlyph($r('sys.symbol.star'))
        .fontSize(iconSize)
        .fontColor([$r('sys.color.font_secondary')])
      Text("暂无收藏")
        .fontColor($r('sys.color.font_secondary'))
        .fontSize(fontSize)
        .margin({ top: 8 })
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
  }

  // --- 1x1 布局 ---
  @Builder
  Size1x1() {
    Column() {
      Row() {
        SymbolGlyph($r('sys.symbol.star_fill'))
          .fontSize(24)
          .fontColor([this.brandColor])
      }
      .width('100%')
      .justifyContent(FlexAlign.Start)

      if (!this.favoriteUuid) {
        this.EmptyView(24, 12)
      } else {
        Column() {
          SymbolGlyph(this.isRunning ? $r("sys.symbol.pause_round_triangle_fill") : $r("sys.symbol.play_round_triangle_fill"))
            .fontSize(48)
            .fontColor([this.brandColor])
            .symbolEffect(new ReplaceSymbolEffect(EffectScope.WHOLE), (this.isRunning ? 1 : 0) + this.trigger)
            .onClick(() => this.toggle())
          
          Text(this.favoriteName)
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('sys.color.font_primary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .margin({ top: 8 })
        }
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .width('100%')
      }
    }
    .padding(12)
    .width('100%')
    .height('100%')
  }

  // --- 2x1 布局 ---
  @Builder
  Size2x1() {
    Column() {
      Row() {
        SymbolGlyph($r('sys.symbol.star_fill'))
          .fontSize(24)
          .fontColor([this.brandColor])
      }
      .width('100%')
      .justifyContent(FlexAlign.Start)
      .margin({ bottom: 8 })

      Row() {
        if (!this.favoriteUuid) {
          this.EmptyView(32, 14)
        } else {
          Column() {
            Text(this.favoriteName)
              .fontSize(24)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('sys.color.font_primary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            
            Text(this.favoriteUuid)
              .fontSize(12)
              .fontColor($r('sys.color.font_secondary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .margin({ top: 2 })
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)

          Column() {
            SymbolGlyph(this.isRunning ? $r("sys.symbol.pause_round_triangle_fill") : $r("sys.symbol.play_round_triangle_fill"))
              .fontSize(56)
              .fontColor([this.brandColor])
              .symbolEffect(new ReplaceSymbolEffect(EffectScope.WHOLE), (this.isRunning ? 1 : 0) + this.trigger)
              .onClick(() => this.toggle())
          }
          .justifyContent(FlexAlign.Center)
          .height('100%')
          .padding({ left: 16 })
        }
      }
      .width('100%')
      .layoutWeight(1)
    }
    .padding(16)
    .width('100%')
    .height('100%')
  }

  // --- 1x2 布局 ---
  @Builder
  Size1x2() {
    Column() {
      Row() {
        SymbolGlyph($r('sys.symbol.star_fill'))
          .fontSize(24)
          .fontColor([this.brandColor])
      }
      .width('100%')
      .justifyContent(FlexAlign.Start)
      .margin({ bottom: 8 })

      if (!this.favoriteUuid) {
        this.EmptyView(32, 14)
      } else {
        Column() {
          SymbolGlyph(this.isRunning ? $r("sys.symbol.pause_round_triangle_fill") : $r("sys.symbol.play_round_triangle_fill"))
            .fontSize(64)
            .fontColor([this.brandColor])
            .symbolEffect(new ReplaceSymbolEffect(EffectScope.WHOLE), (this.isRunning ? 1 : 0) + this.trigger)
            .onClick(() => this.toggle())
          
          Text(this.favoriteName)
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('sys.color.font_primary'))
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .textAlign(TextAlign.Center)
            .margin({ top: 16 })
            
          Text(this.favoriteUuid)
            .fontSize(12)
            .fontColor($r('sys.color.font_secondary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .margin({ top: 4 })
        }
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .width('100%')
      }
    }
    .padding(16)
    .width('100%')
    .height('100%')
  }

  // --- 2x2 布局 ---
  @Builder
  Size2x2() {
    Column() {
      Row() {
        SymbolGlyph($r('sys.symbol.star_fill'))
          .fontSize(24)
          .fontColor([this.brandColor])
      }
      .width('100%')
      .justifyContent(FlexAlign.Start)
      .margin({ bottom: 8 })

      if (!this.favoriteUuid) {
        this.EmptyView(48, 16)
      } else {
        Column() {
          SymbolGlyph(this.isRunning ? $r("sys.symbol.pause_round_triangle_fill") : $r("sys.symbol.play_round_triangle_fill"))
            .fontSize(80)
            .fontColor([this.brandColor])
            .symbolEffect(new ReplaceSymbolEffect(EffectScope.WHOLE), (this.isRunning ? 1 : 0) + this.trigger)
            .onClick(() => this.toggle())
            
          Text(this.favoriteName)
            .fontSize(24)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('sys.color.font_primary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .margin({ top: 20 })
            
          Text(this.favoriteUuid)
            .fontSize(14)
            .fontColor($r('sys.color.font_secondary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .margin({ top: 4 })
            
          if (this.isRunning) {
            Text("正在运行")
              .fontSize(14)
              .fontColor(this.brandColor)
              .margin({ top: 8 })
              .padding({ left: 12, right: 12, top: 4, bottom: 4 })
              .backgroundColor($r('sys.color.comp_background_tertiary'))
              .borderRadius(12)
          }
        }
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .width('100%')
      }
    }
    .padding(16)
    .width('100%')
    .height('100%')
  }

  build() {
    Stack() {
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
  }
}
