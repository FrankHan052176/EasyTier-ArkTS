import { sendFormId, startFavorite } from '../../../util/WidgetAction'

const localStorage = new LocalStorage()

@Entry(localStorage)
@Component
struct Favorite_widgetCard {
  @Watch("updateFormId") @LocalStorageProp('formId') formId: string = 'formId'
  @LocalStorageProp('dim') dim: number = 1
  @LocalStorageProp('favorite_name') favorite_name: string = 'Name'
  @LocalStorageProp('favorite_uuid') favorite_uuid: string = 'UUID'
  @LocalStorageProp('favorite_running') favorite_running: boolean = false
  readonly brandColor: string = 'rgba(255,200,50,1)'

  updateFormId() {
    sendFormId(this, this.formId)
  }

  @Builder
  Logo(size: number = 24) {
    SymbolGlyph($r('sys.symbol.star_fill'))
      .fontSize(size)
      .fontColor([this.brandColor])
  }

  // dim = 2 (2x2) -> Uses Size1x1 visual style from Favorite.ets
  // "The card size 2 is only the size of the component size 1"
  @Builder
  Size2x2() {
    Column() {
      Row() {
        this.Logo(24)
      }
      .width('100%')
      .justifyContent(FlexAlign.Start)

      Column() {
        Column() {
          SymbolGlyph(this.favorite_running ? $r("sys.symbol.pause_round_triangle_fill") :
            $r("sys.symbol.play_round_triangle_fill"))
            .fontSize(48)
            .fontColor([this.brandColor])
            .onClick(() => {
              startFavorite(this, this.formId)
            })
        }

        Text(this.favorite_name)
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
    .padding(16)
    .width('100%')
    .height('100%')
  }

  // dim = 1 (1x2) -> Uses Size2x1 visual style but modified
  // "1*2 left top badge can be changed to right top as background board"
  @Builder
  Size1x2() {
    Row() {
      Column() {
        Text(this.favorite_name)
          .fontSize(20) // Slightly smaller than 24 in 2x1 to fit widget better? Keeping close to 24.
          .fontWeight(FontWeight.Bold)
          .fontColor($r('sys.color.font_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Text(this.favorite_uuid)
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
        SymbolGlyph(this.favorite_running ? $r("sys.symbol.pause_round_triangle_fill") :
          $r("sys.symbol.play_round_triangle_fill"))
          .fontSize(48) // Slightly smaller than 56 in 2x1 to ensure fit
          .fontColor([this.brandColor])
          .onClick(() => {
            startFavorite(this, this.formId)
          })
      }
      .justifyContent(FlexAlign.Center)
      .height('100%')
      .padding({ left: 8 })
    }
    .width('100%')
    .height('100%')
    .padding(8)
  }

  build() {
    Column() {
      if (this.favorite_uuid != "UUID") {
        if (this.favorite_name) {
          if (this.dim === 1) {
            this.Size1x2()
          } else {
            this.Size2x2()
          }
        }else {
          Column() {
            Text("未收藏实例")
              .fontColor($r('sys.color.font_secondary'))
              .fontSize(14)
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
        }
      } else {
        Column() {
          Text("打开app刷新")
            .fontColor($r('sys.color.font_secondary'))
            .fontSize(14)
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('sys.color.comp_background_primary')) // Assuming a background color is needed
  }
}
