import { AppManager } from '../../AppManager'
import { HMRouterMgr } from '@hadss/hmrouter'
import { HMRouterTransitions } from '@hadss/hmrouter-transitions'
import { InstanceSelector } from '../util/InstanceSelector'

@ComponentV2
export struct Instances {
  @Computed
  get w(): number {
    return AppManager.layout.getCompSize('Instances').lane_w
  }

  @Computed
  get h(): number {
    return AppManager.layout.getCompSize('Instances').lane_h
  }

  @Computed
  get uuids() {
    return Array.from(AppManager.data.configUUIDNameMap.keys())
  }

  @Computed
  get selectedUuid() {
    return AppManager.easytier.selected
  }

  select(uuid: string) {
    AppManager.easytier.selected = uuid
  }

  next() {
    if (this.uuids.length === 0) return
    const currentIndex = this.uuids.indexOf(this.selectedUuid ?? "")
    let nextIndex = currentIndex + 1
    if (nextIndex >= this.uuids.length || nextIndex < 0) {
      nextIndex = 0
    }
    this.select(this.uuids[nextIndex])
  }

  toEdit(uuid: string) {
    const animator = HMRouterTransitions.cardLongTake("instance_card_" + uuid, "edit_content");
    AppManager.data.editingInstance = uuid
    HMRouterMgr.push({ pageUrl: 'EditPage', param: uuid, animator: animator });
  }

  toggleFavorite(uuid: string) {

  }

  // --- 1x1 布局 ---
  @Builder
  Size1x1() {
    Column() {
      if (this.uuids.length === 0) {
        this.EmptyView(24, 10)
      } else {
        Row() {
          SymbolGlyph($r('sys.symbol.key_shield'))
            .fontSize(24)
            .fontColor([$r('sys.color.brand')])
        }
        .width('100%')
        .justifyContent(FlexAlign.Start)

        InstanceSelector({
          selectedUuid: this.selectedUuid ?? "",
          onSelect: (uuid: string): void => this.select(uuid)
        })

        Row() {
          Blank()
          SymbolGlyph($r("sys.symbol.square_and_pencil"))
            .fontSize(18)
            .fontColor([$r("sys.color.font_tertiary")])
            .id("instance_card_" + this.selectedUuid)
            .onClick(() => this.toEdit(this.selectedUuid!))
        }
        .width('100%')
      }
    }
    .padding(12)
    .width('100%')
    .height('100%')
  }

  // --- 2x1 布局: 1高2宽 (含收藏) ---
  @Builder
  Size2x1() {
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
          this.IconButton(AppManager.data.isFavorite(this.selectedUuid) ? $r("sys.symbol.star_fill") : $r("sys.symbol.star"),
            (): void => AppManager.data.changeFavorite(this.selectedUuid),
            AppManager.data.isFavorite(this.selectedUuid) ? $r("sys.color.brand") : $r("sys.color.font_primary"))
          
          this.IconButton($r("sys.symbol.square_and_pencil"), (): void => this.toEdit(this.selectedUuid!), 
            $r("sys.color.font_primary"), "instance_card_" + this.selectedUuid)
        }
      }
    }
    .padding(16)
    .width('100%')
    .height('100%')
  }

  // --- 1x2 布局 ---
  @Builder
  Size1x2() {
    Column() {
      Text("实例列表")
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('sys.color.font_primary'))
        .width('100%')
        .margin({ bottom: 12 })

      if (this.uuids.length === 0) {
        this.EmptyView(32, 12)
      } else {
        List({ space: 8 }) {
          ForEach(this.uuids, (uuid: string) => {
            ListItem() {
              this.ListItemView(uuid, false)
            }
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
  }

  // --- 2x2 布局 (含收藏) ---
  @Builder
  Size2x2() {
    Column() {
      Row() {
        Text("所有实例")
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('sys.color.font_primary'))
        Blank()
        Text(this.uuids.length.toString())
          .fontSize(14)
          .fontColor($r('sys.color.font_secondary'))
      }
      .width('100%')
      .margin({ bottom: 12 })

      if (this.uuids.length === 0) {
        this.EmptyView(48, 14)
      } else {
        List({ space: 8 }) {
          ForEach(this.uuids, (uuid: string) => {
            ListItem() {
              this.ListItemView(uuid, true)
            }
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
  }

  @Builder
  ListItemView(uuid: string, showFavorite: boolean) {
    Row() {
      Column() {
        Text(AppManager.data.configUUIDNameMap.get(uuid))
          .fontSize(14)
          .fontWeight(this.selectedUuid === uuid ? FontWeight.Bold : FontWeight.Medium)
          .fontColor(this.selectedUuid === uuid ? $r('sys.color.brand') : $r('sys.color.font_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        
        if (showFavorite) {
          Text(uuid)
            .fontSize(10)
            .fontColor($r('sys.color.font_tertiary'))
            .margin({ top: 2 })
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .onClick(() => this.select(uuid))

      Row({ space: 10 }) {
        if (showFavorite) {
          SymbolGlyph(AppManager.data.isFavorite(uuid) ? $r("sys.symbol.star_fill") : $r("sys.symbol.star"))
            .fontSize(18)
            .fontColor([AppManager.data.isFavorite(uuid) ? $r("sys.color.brand") : $r("sys.color.font_secondary")])
            .onClick(() => AppManager.data.changeFavorite(uuid))
        }
        
        SymbolGlyph($r("sys.symbol.square_and_pencil"))
          .fontSize(18)
          .fontColor([$r("sys.color.font_secondary")])
          .id(this.selectedUuid === uuid ? "instance_card_" + uuid : "")
          .onClick(() => this.toEdit(uuid))
      }
    }
    .width('100%')
    .padding(10)
    .backgroundColor($r('sys.color.comp_background_tertiary'))
    .borderRadius(8)
  }

  @Builder
  IconButton(icon: Resource, action: () => void, color: Resource, id?: string) {
    Column() {
      SymbolGlyph(icon)
        .fontSize(24)
        .fontColor([color])
    }
    .id(id ?? "")
    .width(44)
    .height(44)
    .justifyContent(FlexAlign.Center)
    .backgroundColor($r('sys.color.comp_background_tertiary'))
    .borderRadius(22)
    .onClick(action)
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
    .backgroundColor($r("sys.color.comp_background_primary"))
    .borderRadius(18)
  }
}