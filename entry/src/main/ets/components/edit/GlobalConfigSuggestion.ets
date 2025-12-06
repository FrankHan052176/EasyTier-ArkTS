import { AppManager } from "../../AppManager";
import { FieldValue, updateFieldValue } from "../../class/config/Basic";
import { FieldValueDataSource } from "../../class/FieldValueDataSource";
import { lane } from "../../util/Conversion";
import { ToolButton } from "../util/ToolButtons";
import { getFieldI18Name } from "./FieldEdit";
import { ListFieldValue } from "./ListFieldValue";
import { LengthMetrics } from "@kit.ArkUI";

@ComponentV2
export struct GlobalConfigSuggestions {
  @Param @Require field: string;
  @Param @Require type: string;
  @Local dataSource: FieldValueDataSource = AppManager.data.getDataSource(this.type)
  @Local item_height: number = 0
  private scroller: ListScroller = new ListScroller();

  @Computed
  get comp_height() {
    if (this.dataSource.totalCount() == 0) {
      return 70
    }else if (this.dataSource.totalCount() <= 2) {
      return this.dataSource.totalCount()*this.item_height+(this.dataSource.totalCount()-1)*10
    }else {
      return 2.5*this.item_height+10
    }
  }

  @Builder
  rightButton(value: FieldValue) {
    Row() {
      ToolButton({symbol: $r("sys.symbol.trash"), buttonSize: (lane(1)-20)/3-10, bgColor: $r("sys.color.comp_background_primary"), symbolColor: [$r("sys.color.warning")]})
        .margin({
          left: 10,
          right: 10
        })
        .onClick(() => {
          this.scroller.closeAllSwipeActions()
          animateToImmediately({
            curve: Curve.Ease,
            duration: 300
          }, () => {
            AppManager.data.getDataSource(this.type).del(value)
          })
        })
    }
  }

  @Builder
  content() {
    List({space: 10, scroller: this.scroller}) {
      if (this.dataSource.totalCount() > 0) {
        LazyForEach(this.dataSource, (item: FieldValue) => {
          if (item) {
            ListItem() {
              ListFieldValue({field: this.field, type: this.type, value: item})
                .width('100%')
                .onAreaChange((a,b) => {
                  this.item_height = b.height.valueOf() as number
                })
                .onClick(() => {
                  updateFieldValue(this.type, item)
                })
            }
            .swipeAction({
              end: this.rightButton(item)
            })
          }
        })
      }else {
        ListItem() {
          Column() {
            Row() {
              SymbolGlyph($r("sys.symbol.minus_circle"))
                .margin({right: 8})
                .fontColor([$r("sys.color.font_primary")])
              Text(getFieldI18Name(this.field))
              Text("为空")
            }
          }
          .alignItems(HorizontalAlign.Center)
          .justifyContent(FlexAlign.Center)
          .height(this.comp_height)
          .width('100%')
          .borderRadius(18)
          .backgroundColor($r("sys.color.comp_background_primary"))
        }
      }
    }
    .scrollBar(BarState.Off)
    .fadingEdge(true, {
      fadingEdgeLength: LengthMetrics.vp(8)
    })
    .height(this.comp_height)
    .width('100%')
  }

  @Styles
  backgroundColumn() {
    .width('100%')
    .borderRadius(18)
    .backgroundColor(Color.Transparent)
    .clip(true)
    .padding({left: 8, bottom: 0, right: 8})
  }

  build() {
    Column() {
      Row() {
        Row() {
          SymbolGlyph($r("sys.symbol.arrow_counterclockwise_clock"))
            .fontSize(14)
            .fontColor([$r("sys.color.font_primary")])
            .margin({left: 5, right: 5})
          Text(getFieldI18Name(this.field))
            .fontSize(14)
            .focusable(false)
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
        .justifyContent(FlexAlign.Start)
        .focusable(false)
      }
      .padding({left: 5, bottom: 10, right: 5, top: 10})
      Column() {
        this.content()
      }
      .backgroundColumn()
    }
  }
}