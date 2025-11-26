import { AppManager, Sfp2vp } from '../../AppManager'
import { CompTitle } from './Basic'
import { common } from '@kit.AbilityKit'
import { Logger } from '../../util/Logger'
import { EventHelper } from '../../util/EventHelper'

@Extend(Column)
function comp_bg() {
  .width('100%')
  .height('100%')
  .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
}

@Builder
export function QQ_Content(name: string | Resource, qqgroup: string) {
  Column({space: 6}) {
    Image(name==="App反馈群"?$r("app.media.app"):$r("app.media.easytier"))
      .height("50%")
    Row() {
      Text() {
        SymbolSpan($r("sys.symbol.message_on_message")).fontColor([$r("sys.color.font_primary")]).fontSize(16)
      }
      .margin({right: 5})
      Text(name).maxLines(1).fontColor($r("sys.color.font_primary"))
    }
    .height(Sfp2vp(16))
  }
  .height('100%')
  .width('100%')
  .alignItems(HorizontalAlign.Center)
  .justifyContent(FlexAlign.Start)
  .onClick(() => {
    (AppManager.content.context as common.UIAbilityContext).startAbility({
      uri: "mqqapi://card/show_pslcard?src_type=internal&version=1&uin="+qqgroup+"&card_type=group&source=qrcode"
    }).catch(() => {
      Logger.error(`QQGroupButton::An unexpected error occurred.`, "QQGroups");
    })
  })
}

@ComponentV2
export struct QQGroups {
  @Local groups:string[] = []

  aboutToAppear(): void {
    AppManager.web.updateQQGroups()
    EventHelper.emitterListener("update_qqgroups", (data) => {
      this.groups = data.data!.groups as string[]
    })
  }

  build() {
    Column() {
      CompTitle("QQ群", '#0052d9', ()=>{return -1})
      Swiper() {
        ForEach(this.groups, (qqgroup: string, index: number) => {
          QQ_Content("EasyTier"+(index+1)+"群", qqgroup)
        })
        QQ_Content("App反馈群", "630809530")
      }
      .loop(true)
      .autoPlay(true)
      .interval(4000)
      .width('100%')
      .layoutWeight(100)
      .padding({top: 10, left: 10, right: 10})
    }
    .comp_bg()
  }
}