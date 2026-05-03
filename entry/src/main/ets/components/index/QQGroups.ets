import { AppManager } from '../../AppManager'
import { common } from '@kit.AbilityKit'
import { Logger } from '../../shared/logging/Logger'
import { EventHelper } from '../../util/EventHelper'
import { LightModifier } from '../../class/modifier/SymbolLight'
import { StackLightModifier } from '../../class/modifier/BackgroundLight'

@ComponentV2
export struct QQGroups {
  @Local groups: string[] = []
  @Local lightMod: LightModifier = new LightModifier('#0052d9')
  @Local bgMode: StackLightModifier = new StackLightModifier()
  @Consumer("w") w: number = 1
  @Consumer("h") h: number = 1

  aboutToAppear(): void {
    AppManager.web.updateQQGroups()
    EventHelper.emitterListener("update_qqgroups", (data) => {
      this.groups = data.data!.groups as string[]
    })
  }

  openGroup(qqgroup: string) {
    (AppManager.content.context as common.UIAbilityContext).startAbility({
      uri: "mqqapi://card/show_pslcard?src_type=internal&version=1&uin=" + qqgroup + "&card_type=group&source=qrcode"
    }).catch(() => {
      Logger.error(`QQGroupButton::An unexpected error occurred.`, "QQGroups");
    })
  }

  @Builder
  QQCard(name: string, qqgroup: string) {
    Column() {
      Image(name === "App反馈群" ? $r("app.media.app") : $r("app.media.easytier"))
        .height(this.h === 1 && this.w === 1 ? 32 : 48)
        .objectFit(ImageFit.Contain)
        .margin({ bottom: 8 })

      Text(name)
        .fontSize(14)
        .fontColor($r("sys.color.font_primary"))
        .fontWeight(FontWeight.Medium)
    }
    .width('100%')
    .justifyContent(FlexAlign.Center)
    .onClick(() => this.openGroup(qqgroup))
  }

  @Builder
  ContentSwiper() {
    Swiper() {
      ForEach(this.groups, (qqgroup: string, index: number) => {
        this.QQCard("EasyTier" + (index + 1) + "群", qqgroup)
      })
      this.QQCard("App反馈群", "630809530")
    }
    .loop(true)
    .autoPlay(true)
    .interval(4000)
    .width('100%')
    .height('100%')
    .indicator(false)
  }

  @Builder
  point() {
    Column()
      .size({ width: 1, height: 1 })
      .attributeModifier(this.lightMod)
  }

  @Builder
  Logo() {
    SymbolGlyph($r('sys.symbol.message_on_message'))
      .fontSize(24)
      .fontColor(['#0052d9'])
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
        this.ContentSwiper()
      }
      .layoutWeight(1)
      .width('100%')
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

      Column() {
        this.ContentSwiper()
      }
      .layoutWeight(1)
      .width('100%')
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
        this.Logo()
      }
      .width('100%')
      .justifyContent(FlexAlign.Start)
      .margin({ bottom: 8 })

      Column() {
        this.ContentSwiper()
      }
      .layoutWeight(1)
      .width('100%')
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
        this.Logo()

        Blank()

        Text((this.groups.length + 1).toString())
          .fontSize(14)
          .fontColor($r('sys.color.font_secondary'))
      }
      .width('100%')
      .margin({ bottom: 8 })

      Column() {
        this.ContentSwiper()
      }
      .layoutWeight(1)
      .width('100%')
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
    .borderRadius(18)
    .attributeModifier(this.bgMode)
    .backgroundColor($r("sys.color.comp_background_primary"))
  }
}
