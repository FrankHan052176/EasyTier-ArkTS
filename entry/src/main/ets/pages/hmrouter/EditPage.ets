import { ConfigField, ContentUtil } from '../../ContentUtil'
import { FieldEdit } from '../../components/edit/FieldEdit'
import { HMRouter, HMRouterMgr } from '@hadss/hmrouter'
import { deviceInfo } from '@kit.BasicServicesKit'
import { HdsNavigation, HdsNavigationTitleMode, ScrollEffectType, HdsNavigationAttribute } from '@kit.UIDesignKit'
import { LengthMetrics } from '@kit.ArkUI'
import { AppManager } from '../../AppManager'
import { HdsMenuButton, MenuButton } from '../Components'
import { SheetContentBuilder, SheetTitleBuilder } from '../../components/sheet/Basic'
import { EventHelper } from '../../util/EventHelper'
import { WindowUtil } from '../../WindowUtil'
import { Logger } from '../../util/Logger'

@HMRouter({ pageUrl: "EditPage" })
@ComponentV2
export struct EditPage {
  @Local uuid: string | null = null;
  @Local name: string | null = null;
  @Local sheet: boolean = false
  @Local sheet_type: string = ""

  aboutToAppear(): void {
    this.uuid = HMRouterMgr.getCurrentParam() as string;
    this.name = AppManager.data.configUUIDNameMap.get(this.uuid)!
    EventHelper.emitterListener("edit_open_sheet", (data) => {
      this.sheet_type = data.data!.type as string
      this.sheet = true
    })
    EventHelper.emitterListener("edit_close_sheet", () => {
      this.sheet = false
    })
  }

  aboutToDisappear(): void {
    AppManager.data.editingInstance = undefined
  }

  @Builder
  content() {
    Swiper() {
      List({space: 20}) {
        if (deviceInfo.sdkApiVersion >= 20) {
          ListItem()
            .width('100%')
            .height(56)
        }
        ForEach(ContentUtil.basicFields, (field: ConfigField) => {
          ListItem(){
            FieldEdit({field: field})
              .width('100%')
          }
        })
        ListItem()
          .width('100%')
          .height(150)
      }
      .width('100%')
      .height('100%')
      .scrollBar(BarState.Off)
      .chainAnimation(true)
      .edgeEffect(EdgeEffect.None)
      .padding({left: 20, right: 20})
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      Scroll() {
        Column({space: 20}) {
          if (deviceInfo.sdkApiVersion >= 20) {
            Row()
              .width('100%')
              .height(56)
          }
          FieldEdit({field: ContentUtil.flagField})
            .width('100%')
          Row()
            .width('100%')
            .height(150)
        }
      }
      .width('100%')
      .height('100%')
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.None)
      .padding({left: 20, right: 20})
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      List({space: 20}) {
        if (deviceInfo.sdkApiVersion >= 20) {
          ListItem()
            .width('100%')
            .height(56)
        }
        ForEach(ContentUtil.advancedFields, (field: ConfigField) => {
          ListItem(){
            FieldEdit({field: field})
              .width('100%')
          }
        })
        ListItem()
          .width('100%')
          .height(150)
      }
      .width('100%')
      .height('100%')
      .scrollBar(BarState.Off)
      .chainAnimation(true)
      .edgeEffect(EdgeEffect.None)
      .padding({left: 20, right: 20})
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      List({space: 20}) {
        if (deviceInfo.sdkApiVersion >= 20) {
          ListItem()
            .width('100%')
            .height(56)
        }
        ForEach(ContentUtil.otherFields, (field: ConfigField) => {
          ListItem(){
            FieldEdit({field: field})
              .width('100%')
          }
        })
        ListItem()
          .width('100%')
          .height(150)
      }
      .width('100%')
      .height('100%')
      .scrollBar(BarState.Off)
      .chainAnimation(true)
      .edgeEffect(EdgeEffect.None)
      .padding({left: 20, right: 20})
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    }
    .width('100%')
    .height('100%')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .id("edit_content")
    .displayCount(WindowUtil.uiType/2)
    .loop(false)
    .indicator(DotIndicator.dot().top(46))
  }

  build() {
    Column() {
      if (deviceInfo.sdkApiVersion >= 20) {
        HdsNavigation() {
          this.content()
        }
        .titleBar({
          style: {
            scrollEffectOpts: {
              enableScrollEffect: true,
              scrollEffectType: ScrollEffectType.GRADUAL_BLUR,
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
                  backgroundColor: $r("sys.color.interactive_hover")
                },
                backIconStyle: {
                  backgroundColor: $r("sys.color.interactive_hover"),
                  iconColor: $r("sys.color.font_primary")
                }
              }
            }
          },
          content: {
            title: {
              mainTitle: this.name!,
              subTitle: this.uuid!
            },
            menu: {
              value: [
                HdsMenuButton("favorite", AppManager.data.isFavorite(this.uuid!)?$r("sys.symbol.star_fill"):$r("sys.symbol.star"), () => {
                  AppManager.data.changeFavorite(this.uuid!)
                }),
                HdsMenuButton("share", $r("sys.symbol.rectangle_and_arrowshape_turn_up_right_fill"), () => {
                  // TODO 分享
                }),
                HdsMenuButton("delete", $r("sys.symbol.trash"), () => {
                  HMRouterMgr.pop()
                  AppManager.data.delConfig(this.uuid!)
                })
              ]
            }
          }
        })
        .mode(NavigationMode.Stack)
        .titleMode(HdsNavigationTitleMode.MINI)
        .hideBackButton(false)
        .hideTitleBar(false)
      }else {
        Navigation() {
          this.content()
        }
        .mode(NavigationMode.Stack)
        .titleMode(NavigationTitleMode.Mini)
        .title({
          main: this.name!,
          sub: this.uuid!
        }, {
          backgroundColor: $r('sys.color.background_secondary')
        })
        .menus([
          MenuButton("favorite", AppManager.data.isFavorite(this.uuid!)?$r("sys.symbol.star_fill"):$r("sys.symbol.star"), () => {
            AppManager.data.changeFavorite(this.uuid!)
          }),
          MenuButton("share", $r("sys.symbol.rectangle_and_arrowshape_turn_up_right_fill"), () => {
            // TODO 分享
          }),
          MenuButton("delete", $r("sys.symbol.trash"), () => {
            HMRouterMgr.pop()
            AppManager.data.delConfig(this.uuid!)
          }),
          MenuButton("toml", $r("sys.symbol.doc_plaintext"), () => {
            // TODO 输出Toml
          }),
        ])
      }
    }
    .backgroundColor($r('sys.color.background_secondary'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .bindSheet(this.sheet, SheetContentBuilder(this.sheet_type), {
      height: SheetSize.FIT_CONTENT,
      preferType: SheetType.CENTER,
      showClose: false,
      dragBar: false,
      blurStyle: BlurStyle.Thin,
      title: SheetTitleBuilder(this.sheet_type),
      onWillDismiss: () => {
        this.sheet = false
      }
    })
  }
}