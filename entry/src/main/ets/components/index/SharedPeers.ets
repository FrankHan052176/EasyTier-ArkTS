import { AppManager } from '../../AppManager'
import { LightModifier } from '../../class/modifier/SymbolLight'
import { hdsEffect } from '@kit.UIDesignKit'
import { StackLightModifier } from '../../class/modifier/BackgroundLight'

@ComponentV2
export struct SharedPeers {
  @Local lightMod: LightModifier = new LightModifier('rgba(0,230,118,1)')
  @Local bgMode: StackLightModifier = new StackLightModifier()
  @Computed
  get w(): number {
    return AppManager.layout.getCompSize('SharedPeers').lane_w
  }

  @Computed
  get h(): number {
    return AppManager.layout.getCompSize('SharedPeers').lane_h
  }

  readonly brandColor: string = 'rgba(0,230,118,1)'
  readonly infoText: string = "为了 EasyTier和MC 社区的长远发展，我们会尽快完成完全合规化运营，在此之前 社区共享节点 会临时关闭，在不久的将来，他会与各位重新见面。"

  @Builder
  point() {
    Column()
      .size({width:1,height:1})
      .attributeModifier(this.lightMod)
  }

  @Builder
  Logo() {
    SymbolGlyph($r('sys.symbol.share'))
      .fontSize(24)
      .fontColor([this.brandColor])
      .overlay(this.point,{
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
        SymbolGlyph($r('sys.symbol.exclamationmark_circle'))
           .fontSize(32)
           .fontColor([$r('sys.color.font_secondary')])
        Text("暂时关闭")
          .fontSize(12)
          .fontColor($r('sys.color.font_secondary'))
          .margin({ top: 4 })
      }
      .layoutWeight(1)
      .width('100%')
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

      Column() {
        Text(this.infoText)
          .fontSize(12)
          .fontColor($r('sys.color.font_primary'))
          .maxLines(3)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .layoutWeight(1)
      .width('100%')
      .justifyContent(FlexAlign.Center)
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
        Text(this.infoText)
          .fontSize(12)
          .fontColor($r('sys.color.font_primary'))
          .maxLines(6)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .layoutWeight(1)
      .width('100%')
      .justifyContent(FlexAlign.Center)
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
      }
      .width('100%')
      .justifyContent(FlexAlign.Start)
      .margin({ bottom: 8 })

      Column() {
         Text(this.infoText)
          .fontSize(14)
          .fontColor($r('sys.color.font_primary'))
      }
      .layoutWeight(1)
      .width('100%')
      .justifyContent(FlexAlign.Center)
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
  }
}