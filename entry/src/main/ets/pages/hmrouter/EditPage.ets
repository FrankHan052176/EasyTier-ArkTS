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
import { compressStr } from '../../CompressUtil'
import { mappedJson } from '../../MappedUtil'
import { harmonyShare, systemShare } from '@kit.ShareKit'
import { uniformTypeDescriptor } from '@kit.ArkData'
import { Logger } from '../../util/Logger'
import { common } from '@kit.AbilityKit'
import { buildShareData } from '../../util/ShareUtil'

@HMRouter({ pageUrl: "EditPage" })
@ComponentV2
export struct EditPage {
  @Local uuid: string | null = null;
  @Local sheet: boolean = false
  @Local sheet_type: string = ""

  @Computed
  get name() {
    if (this.uuid) {
      return AppManager.data.configUUIDNameMap.get(this.uuid)
    }
    return ""
  }

  aboutToAppear(): void {
    this.uuid = HMRouterMgr.getCurrentParam() as string;
    EventHelper.emitterListener("edit_open_sheet", (data) => {
      this.sheet_type = data.data!.type as string
      this.sheet = true
    })
    EventHelper.emitterListener("edit_close_sheet", () => {
      this.sheet = false
    })
    harmonyShare.on('knockShare', (target) => {
      this.immersiveCallback(target)
    });
    if (deviceInfo.sdkApiVersion >= 20) {
      harmonyShare.on('gesturesShare', (target) => {
        this.immersiveCallback(target)
      });
    }
  }

  aboutToDisappear(): void {
    harmonyShare.off('knockShare', (target) => {
      this.immersiveCallback(target)
    });
    if (deviceInfo.sdkApiVersion >= 20) {
      harmonyShare.off('gesturesShare', (target) => {
        this.immersiveCallback(target)
      });
    }
    AppManager.data.editingInstance = undefined
  }

  @Builder
  content() {
    Swiper() {
      List({ space: 20 }) {
        if (deviceInfo.sdkApiVersion >= 20) {
          ListItem()
            .width('100%')
            .height(56)
        }
        ForEach(ContentUtil.basicFields, (field: ConfigField) => {
          ListItem() {
            FieldEdit({ field: field })
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
      .padding({ left: 20, right: 20 })
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

      Scroll() {
        Column({ space: 20 }) {
          if (deviceInfo.sdkApiVersion >= 20) {
            Row()
              .width('100%')
              .height(56)
          }
          FieldEdit({ field: ContentUtil.flagField })
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
      .padding({ left: 20, right: 20 })
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

      List({ space: 20 }) {
        if (deviceInfo.sdkApiVersion >= 20) {
          ListItem()
            .width('100%')
            .height(56)
        }
        ForEach(ContentUtil.advancedFields, (field: ConfigField) => {
          ListItem() {
            FieldEdit({ field: field })
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
      .padding({ left: 20, right: 20 })
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

      List({ space: 20 }) {
        if (deviceInfo.sdkApiVersion >= 20) {
          ListItem()
            .width('100%')
            .height(56)
        }
        ForEach(ContentUtil.otherFields, (field: ConfigField) => {
          ListItem() {
            FieldEdit({ field: field })
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
      .padding({ left: 20, right: 20 })
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    }
    .width('100%')
    .height('100%')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .id("edit_content")
    .displayCount(WindowUtil.uiType / 2)
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
                  backgroundColor: $r("sys.color.interactive_hover"),
                  iconColor: $r("sys.color.font_primary")
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
                HdsMenuButton($r("app.string.i18_favorite"),
                  AppManager.data.isFavorite(this.uuid!) ? $r("sys.symbol.star_fill") : $r("sys.symbol.star"), () => {
                    AppManager.data.changeFavorite(this.uuid!)
                  }),
                HdsMenuButton($r("app.string.i18_share"), $r("sys.symbol.rectangle_and_arrowshape_turn_up_right_fill"),
                  async () => {
                    let config = AppManager.easytier.getEditingConfig()
                    if (config) {
                      buildShareData(config, (data) => {
                        let controller: systemShare.ShareController = new systemShare.ShareController(data);
                        let uiContext: UIContext = this.getUIContext();
                        let context: common.UIAbilityContext = uiContext.getHostContext() as common.UIAbilityContext;
                        controller.show(context, {
                          selectionMode: systemShare.SelectionMode.SINGLE,
                          previewMode: systemShare.SharePreviewMode.DEFAULT,
                          excludedAbilities: [systemShare.ShareAbilityType.PRINT,
                            systemShare.ShareAbilityType.SAVE_TO_SUPERHUB]
                        }).catch(() => {
                          Logger.error(`[Index] systemShareConfig::An unexpected error occurred.`);
                        })
                      }, this.name, this.uuid)
                    }
                  }),
                HdsMenuButton($r("app.string.i18_delete"), $r("sys.symbol.trash"), () => {
                  HMRouterMgr.pop()
                  AppManager.data.delConfig(this.uuid!)
                }),
                HdsMenuButton($r("app.string.i18_rename"), $r("sys.symbol.pencil_line_1"), () => {
                  EventHelper.emitterPublish("edit_open_sheet", {
                    data: {
                      type: "rename"
                    }
                  })
                })
              ]
            }
          }
        })
        .mode(NavigationMode.Stack)
        .titleMode(HdsNavigationTitleMode.MINI)
        .hideBackButton(false)
        .hideTitleBar(false)
      } else {
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
          MenuButton($r("app.string.i18_favorite"),
            AppManager.data.isFavorite(this.uuid!) ? $r("sys.symbol.star_fill") : $r("sys.symbol.star"), () => {
              AppManager.data.changeFavorite(this.uuid!)
            }),
          MenuButton($r("app.string.i18_share"), $r("sys.symbol.rectangle_and_arrowshape_turn_up_right_fill"), () => {
            // TODO 分享
          }),
          MenuButton($r("app.string.i18_delete"), $r("sys.symbol.trash"), () => {
            HMRouterMgr.pop()
            AppManager.data.delConfig(this.uuid!)
          }),
          MenuButton($r("app.string.i18_rename"), $r("sys.symbol.pencil_line_1"), () => {
            EventHelper.emitterPublish("edit_open_sheet", {
              data: {
                type: "rename"
              }
            })
          })
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
      onWillDismiss: (action) => {
        if (action.reason != DismissReason.SLIDE_DOWN) {
          action.dismiss()
          this.sheet = false
        }
      }
    })
  }

  private immersiveCallback(sharableTarget: harmonyShare.SharableTarget) {
    let config = AppManager.data.configUUIDMap.get(this.uuid ?? "")
    if (config) {
      buildShareData(config, (data) => {
        sharableTarget.share(data);
      }, this.name, this.uuid)
    }
  }
}