import { AppManager } from '../../AppManager'
import { HMRouterMgr } from '@hadss/hmrouter'
import { HMRouterTransitions } from '@hadss/hmrouter-transitions'
import { InstanceSelector } from '../util/InstanceSelector'
import { LightModifier } from '../../class/modifier/SymbolLight'
import { StackLightModifier } from '../../class/modifier/BackgroundLight'

@ComponentV2
export struct Instances {
  @Local lightMod: LightModifier = new LightModifier($r('sys.color.brand'))
  @Local bgMode: StackLightModifier = new StackLightModifier()
  @Consumer("w") w: number = 1
  @Consumer("h") h: number = 1

  @Computed
  get uuids() {
    return AppManager.easytier.getAllConfigIds()
  }

  @Computed
  get selectedUuid() {
    return AppManager.uiState.selected
  }

  @Computed
  get isFavorite() {
    if (AppManager.uiState.selected) {
      return AppManager.uiState.selected === AppManager.uiState.favorite
    } else {
      return false
    }
  }

  @Computed
  get favoriteIcon() {
    return this.isFavorite ? $r("sys.symbol.star_fill") : $r("sys.symbol.star")
  }

  select(uuid: string) {
    AppManager.uiState.selected = uuid
  }

  next() {
    if (this.uuids.length === 0) {
      return
    }
    const currentIndex = this.uuids.indexOf(this.selectedUuid ?? "")
    let nextIndex = currentIndex + 1
    if (nextIndex >= this.uuids.length || nextIndex < 0) {
      nextIndex = 0
    }
    this.select(this.uuids[nextIndex])
  }

  toEdit(uuid: string) {
    const animator = HMRouterTransitions.cardLongTake("instance_card_" + uuid, "edit_content");
    AppManager.uiState.editingInstance = uuid
    HMRouterMgr.push({ pageUrl: 'EditPage', param: {uuid: uuid, unsafe: true}, animator: animator});
  }

  @Builder
  point() {
    Column()
      .size({ width: 1, height: 1 })
      .attributeModifier(this.lightMod)
  }

  @Builder
  Logo() {
    SymbolGlyph($r('sys.symbol.key_shield'))
      .fontSize(24)
      .fontColor([$r('sys.color.brand')])
      .overlay(this.point, {
        align: Alignment.Center
      })
  }

  @Builder
  Size1x1() {
    Column() {
      if (this.uuids.length === 0) {
        this.EmptyView(24, 10)
      } else {
        Row() {
          this.Logo()
          Blank()
          Text(this.uuids.length.toString())
            .fontSize(14)
            .fontColor($r('sys.color.font_secondary'))
        }
        .width('100%')

        Column() {
          InstanceSelector({
            selectedUuid: this.selectedUuid ?? "",
            onSelect: (uuid: string): void => this.select(uuid)
          })
        }
        .layoutWeight(1)
        .width('100%')
        .alignItems(HorizontalAlign.Center)
        .justifyContent(FlexAlign.Center)

        Row() {
          Blank()
          if (this.selectedUuid) {
            SymbolGlyph($r("sys.symbol.square_and_pencil"))
              .fontSize(18)
              .fontColor([$r("sys.color.font_tertiary")])
              .onClick(() => this.toEdit(this.selectedUuid!))
              .transition(TransitionEffect.OPACITY.animation({ duration: 300 }))
          }
        }
        .width('100%')
      }
    }
    .padding(16)
    .width('100%')
    .height('100%')
    .id("instance_card_" + this.selectedUuid)
  }

  // --- 2x1 布局: 1高2宽 (含收藏) ---
  @Builder
  Size2x1() {
    Column() {
      Row() {
        this.Logo()
        Blank()
        Text(this.uuids.length.toString())
          .fontSize(14)
          .fontColor($r('sys.color.font_secondary'))
      }
      .width('100%')
      .margin({ bottom: 8 })

      Row() {
        if (this.uuids.length === 0) {
          this.EmptyView(32, 12)
        } else {
          InstanceSelector({
            selectedUuid: this.selectedUuid ?? "",
            onSelect: (uuid: string): void => this.select(uuid)
          })
            .layoutWeight(1)

          Row({ space: 12 }) {
            if (this.selectedUuid) {
              this.IconButton(true,
                (): void => AppManager.data.changeFavorite(this.selectedUuid))

              this.IconButton(false, (): void => this.toEdit(this.selectedUuid!))
            }
          }
          .transition(TransitionEffect.OPACITY.animation({ duration: 300 }))
        }
      }
      .width('100%')
      .layoutWeight(1)
    }
    .padding(16)
    .width('100%')
    .height('100%')
    .id("instance_card_" + this.selectedUuid)
  }

  // --- 1x2 布局 ---
  @Builder
  Size1x2() {
    Column() {
      Row() {
        this.Logo()
        Blank()
        Text(this.uuids.length.toString())
          .fontSize(14)
          .fontColor($r('sys.color.font_secondary'))
      }
      .width('100%')
      .margin({ bottom: 8 })

      if (this.uuids.length === 0) {
        this.EmptyView(32, 12)
      } else {
        List({ space: 8 }) {
          ForEach(this.uuids, (uuid: string) => {
            ListItem() {
              this.ListItemView(uuid, false)
            }
            .swipeAction({ end: this.DeleteAction(uuid) })
          })
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Off)
      }
    }
    .padding(16)
    .width('100%')
    .height('100%')
    .id("instance_card_" + this.selectedUuid)
  }

  // --- 2x2 布局 (含收藏) ---
  @Builder
  Size2x2() {
    Column() {
      Row() {
        this.Logo()
        Blank()
        Text(this.uuids.length.toString())
          .fontSize(14)
          .fontColor($r('sys.color.font_secondary'))
      }
      .width('100%')
      .margin({ bottom: 8 })

      if (this.uuids.length === 0) {
        this.EmptyView(48, 14)
      } else {
        List({ space: 8 }) {
          ForEach(this.uuids, (uuid: string) => {
            ListItem() {
              this.ListItemView(uuid, true)
            }
            .swipeAction({ end: this.DeleteAction(uuid) })
          })
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Off)
      }
    }
    .padding(16)
    .width('100%')
    .height('100%')
    .id("instance_card_" + this.selectedUuid)
  }

  @Builder
  ListItemView(uuid: string, showFavorite: boolean) {
    Row() {
      Column() {
        Text(AppManager.easytier.getConfigName(uuid) ?? uuid)
          .fontSize(14)
          .fontWeight(this.selectedUuid === uuid ? FontWeight.Bold : FontWeight.Medium)
          .fontColor(this.selectedUuid === uuid ? $r('sys.color.brand') : $r('sys.color.font_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Text(uuid)
          .fontSize(10)
          .fontColor($r('sys.color.font_tertiary'))
          .margin({ top: 2 })
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Row({ space: 12 }) {
        if (showFavorite) {
          SymbolGlyph(AppManager.data.isFavorite(uuid) ? $r("sys.symbol.star_fill") : $r("sys.symbol.star"))
            .fontSize(24)
            .fontColor([AppManager.data.isFavorite(uuid) ? 'rgba(255,200,50,1)' : $r("sys.color.font_secondary")])
            .onClick(() => AppManager.data.changeFavorite(uuid))
        }

        SymbolGlyph($r("sys.symbol.square_and_pencil"))
          .fontSize(24)
          .fontColor([$r("sys.color.font_secondary")])
          .onClick(() => this.toEdit(uuid))
      }
    }
    .width('100%')
    .padding(10)
    .backgroundColor($r('sys.color.comp_background_tertiary'))
    .borderRadius(8)
    .onClick(() => this.select(uuid))
  }

  @Builder
  IconButton(favorite: boolean, action: () => void) {
    Column() {
      SymbolGlyph(favorite ? this.favoriteIcon : $r("sys.symbol.square_and_pencil"))
        .fontSize(24)
        .fontColor([this.isFavorite && favorite ? 'rgba(255,200,50,1)' : $r("sys.color.font_primary")])
    }
    .width(44)
    .height(44)
    .justifyContent(FlexAlign.Center)
    .backgroundColor($r('sys.color.comp_background_tertiary'))
    .borderRadius(12)
    .onClick(action)
  }

  @Builder
  DeleteAction(uuid: string) {
    Row() {
      Button({ type: ButtonType.Circle }) {
        SymbolGlyph($r('sys.symbol.trash'))
          .fontSize(22)
          .fontColor([Color.White])
      }
      .width(40)
      .height(40)
      .backgroundColor($r('sys.color.warning'))
      .onClick(() => {
        AppManager.data.delConfig(uuid)
      })
    }
    .justifyContent(FlexAlign.Center)
    .padding({ left: 10 })
  }

  @Builder
  EmptyView(iconSize: number, fontSize: number) {
    Column() {
      SymbolGlyph($r('sys.symbol.link_slash'))
        .fontSize(iconSize)
        .fontColor([$r('sys.color.font_secondary')])
      Text("暂无实例")
        .fontColor($r('sys.color.font_secondary'))
        .fontSize(fontSize)
        .margin({ top: 8 })
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
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
    .borderRadius(18)
    .attributeModifier(this.bgMode)
    .backgroundColor($r("sys.color.comp_background_primary"))
  }
}
