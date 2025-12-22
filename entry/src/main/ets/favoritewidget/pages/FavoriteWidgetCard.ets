let storage = new LocalStorage();

@Entry(storage)
@Component
struct FavoriteWidgetCard {
  @LocalStorageProp('isRunning') isRunning: boolean = false;
  @LocalStorageProp('favoriteName') favoriteName: string = "无收藏";
  @LocalStorageProp('favoriteUuid') favoriteUuid: string = "";
  @LocalStorageProp('formDimension') formDimension: number = 1;

  readonly brandColor: string = 'rgba(255,200,50,1)';
  readonly ACTION_TYPE_ROUTER = 'router';
  readonly ACTION_TYPE_CALL = 'call';
  readonly ABILITY_NAME = 'EntryAbility';

  toggle() {
    postCardAction(this, {
      action: this.ACTION_TYPE_CALL,
      abilityName: this.ABILITY_NAME,
      params: {
        method: 'toggleFavorite'
      }
    });
  }

  openApp() {
    postCardAction(this, {
      action: this.ACTION_TYPE_ROUTER,
      abilityName: this.ABILITY_NAME,
      params: {
        target: 'main'
      }
    });
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
    .onClick(() => this.openApp())
  }

  @Builder
  Size1x2() {
    Row() {
      if (!this.favoriteUuid) {
        this.EmptyView(32, 14)
      } else {
        Column() {
          Text("收藏实例")
            .fontSize(12)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('sys.color.font_primary'))
          Text(this.favoriteName)
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('sys.color.font_primary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .margin({ top: 4 })
          
          Text(this.favoriteUuid)
            .fontSize(10)
            .fontColor($r('sys.color.font_secondary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .margin({ top: 2 })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .onClick(() => this.openApp())

        Column() {
          SymbolGlyph(this.isRunning ? $r("sys.symbol.pause_round_triangle_fill") : $r("sys.symbol.play_round_triangle_fill"))
            .fontSize(40)
            .fontColor([this.brandColor])
            .onClick(() => this.toggle())
        }
        .justifyContent(FlexAlign.Center)
        .height('100%')
        .padding({ left: 12 })
      }
    }
    .padding(12)
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.SpaceBetween)
  }

  // --- 2x2 Layout (Medium Card) ---
  @Builder
  Size2x2() {
    Column() {
      Row() {
        Text("收藏实例")
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('sys.color.font_primary'))
        Blank()
        if (this.favoriteUuid) {
           SymbolGlyph($r('sys.symbol.star_fill'))
            .fontSize(18)
            .fontColor([this.brandColor])
        }
      }
      .width('100%')
      .margin({ bottom: 8 })
      .onClick(() => this.openApp())

      if (!this.favoriteUuid) {
        this.EmptyView(48, 16)
      } else {
        Column() {
          SymbolGlyph(this.isRunning ? $r("sys.symbol.pause_round_triangle_fill") : $r("sys.symbol.play_round_triangle_fill"))
            .fontSize(60)
            .fontColor([this.brandColor])
            .onClick(() => this.toggle())
            
          Text(this.favoriteName)
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('sys.color.font_primary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .margin({ top: 16 })
            .onClick(() => this.openApp())
            
          Text(this.favoriteUuid)
            .fontSize(12)
            .fontColor($r('sys.color.font_secondary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .margin({ top: 4 })
            .onClick(() => this.openApp())
            
          if (this.isRunning) {
            Text("正在运行")
              .fontSize(12)
              .fontColor(this.brandColor)
              .margin({ top: 8 })
              .padding({ left: 10, right: 10, top: 4, bottom: 4 })
              .backgroundColor($r('sys.color.comp_background_tertiary'))
              .borderRadius(10)
              .onClick(() => this.openApp())
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
    Row() {
      // Dimension 1 is 1*2 (Small)
      if (this.formDimension === 1) {
        this.Size1x2()
      } else {
        // Default to 2x2 for other sizes for now
        this.Size2x2()
      }
    }
    .height('100%')
    .width('100%')
    .backgroundColor($r('sys.color.comp_background_primary'))
  }
}
