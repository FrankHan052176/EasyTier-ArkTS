import { FieldValue } from "../../class/config/Basic";
import { NetworkConfig } from "../../protobuf/api_manage";
import { Cidr, CidrBuilder, setEditValue_Cidr } from "../../class/config/Cidr";
import { hdsEffect } from "@kit.UIDesignKit";
import { uiAppearance } from "@kit.ArkUI";
import { lane } from "../../util/Conversion";
import { deviceInfo } from "@kit.BasicServicesKit";
import { ContentUtil } from "../../ContentUtil";
import { ToolButton } from "../../pages/Components";
import { EventHelper } from "../../util/EventHelper";
import { setEditValue_Url, Url, UrlBuilder } from "../../class/config/Url";
import { IP, IPBuilder, setEditValue_IP } from "../../class/config/IP";
import {
  NetworkName, NetworkNameBuilder, setEditValue_NetworkName } from "../../class/config/NetworkName";
import { PortForward, PortForwardBuilder } from "../../class/config/PortForward";
import { AppManager } from "../../AppManager";

@Extend(Row)
function LightEffect() {
  .visualEffect(new hdsEffect.HdsEffectBuilder().pointLight({
    illuminatedType: hdsEffect.PointLightIlluminatedType.BORDER,
  }).buildEffect())
}

@ComponentV2
struct Builders {
  @Param @Require value: FieldValue
  @Param @Require type: string

  build() {
    if (this.type === "cidr" || this.type === "route") {
      CidrBuilder(this.value as Cidr)
    }else if (this.type === "peer" || this.type === "listener" || this.type === "mappedListener") {
      UrlBuilder(this.value as Url)
    }else if (this.type === "ip") {
      IPBuilder(this.value as IP)
    }else if (this.type === "string") {
      NetworkNameBuilder(this.value as NetworkName)
    }else if (this.type === "port_forward") {
      PortForwardBuilder(this.value as PortForward)
    }
  }
}

@ComponentV2
export struct ListFieldValue {
  @Param @Require config: NetworkConfig;
  @Param @Require field: string;
  @Param @Require type: string;
  @Param @Require item: FieldValue;
  @Local enable: boolean = false;
  @Local intensity: number = 0;
  @Local offsetX: number = 0;
  private scroller: ListScroller = new ListScroller();

  aboutToAppear(): void {
    this.enable = (this.config[ContentUtil.safeFieldName(this.field)] as string[]).indexOf(this.item.toString()) >= 0
    this.intensity = this.enable?1:0
    EventHelper.emitterListener("click_edit", () => {
      try {
        this.scroller.closeAllSwipeActions();
      } catch (error) {}
    })
  }

  @Builder
  LightPoint() {
    Flex()
      .width(1)
      .height(1)
      .visualEffect(new hdsEffect.HdsEffectBuilder().pointLight({
        illuminatedType: hdsEffect.PointLightIlluminatedType.BORDER,
        options: {
          color: uiAppearance.getDarkMode() === 0?"#FFFFFF":"#0a59f7",
          intensity: this.intensity,
          height: lane(1)*1,
          bloom: uiAppearance.getDarkMode() === 0?1:0
        }
      }).buildEffect())
      .animation({
        curve: Curve.Ease,
        duration: 300
      })
  }

  @Styles
  backgroundStyle() {
    .width('100%')
    .borderRadius(12)
    .backgroundColor($r("sys.color.interactive_hover"))
    .clickEffect({
      level: ClickEffectLevel.LIGHT
    })
    .onClick(() => {
      this.click()
    })
    .clip(true)
    .gesture(
      SwipeGesture({fingers: 1, direction: SwipeDirection.Horizontal})
        .onAction((event) => {
          if (event.angle < 0) {
            this.offsetX = Math.max(event.offsetX, -30)
          }
        })
    )
    .offset({
      x: this.offsetX
    })
  }

  click() {
    const pos = (this.config[ContentUtil.safeFieldName(this.field)] as string[]).indexOf(this.item.toString())
    if (pos >= 0) {
      (this.config[ContentUtil.safeFieldName(this.field)] as string[]).splice(pos, 1)
    }else {
      (this.config[ContentUtil.safeFieldName(this.field)] as string[]).push(this.item.toString())
    }
    this.enable = !this.enable
    this.intensity = this.enable?1:0
  }

  delete() {
    const pos = (this.config[ContentUtil.safeFieldName(this.field)] as string[]).indexOf(this.item.toString())
    if (pos >= 0) {
      (this.config[ContentUtil.safeFieldName(this.field)] as string[]).splice(pos, 1)
    }
    this.enable = false
    this.intensity = 0
    animateToImmediately({
      curve: Curve.Ease,
      duration: 300
    }, () => {
      AppManager.data.getDataSource(this.type).del(this.item)
    })
  }

  @Builder
  rightButton() {
    Row() {
      ToolButton({symbol: $r("sys.symbol.square_and_pencil"), buttonSize: (lane(1)-20)/3-10})
        .margin({
          left: 10
        })
        .onClick(() => {
          switch (this.type) {
            case "route":
            case "cidr": {
              setEditValue_Cidr(this.item as Cidr)
              break;
            }
            case "mappedListener":
            case "listener":
            case "peer": {
              setEditValue_Url(this.item as Url)
              break;
            }
            case "ip": {
              setEditValue_IP(this.item as IP)
              break;
            }
            case "string": {
              setEditValue_NetworkName(this.item as NetworkName)
              break;
            }
            case "port_forward": {
              // TODO 端口转发
              break;
            }
          }
          this.scroller.closeAllSwipeActions();
          EventHelper.emitterPublish("edit_open_sheet",{
            data: {
              type: "edit_"+this.type+"_"+this.field
            }
          })
        })
      ToolButton({symbol: $r("sys.symbol.trash"), buttonSize: (lane(1)-20)/3-10, symbolColor: [$r("sys.color.warning")]})
        .margin({
          left: 10,
          right: 10
        })
        .onClick(() => {
          this.delete()
        })
    }
  }

  @Computed
  get comp_height() {
    switch (this.type) {
      case "ip":
      case "string":
      case "cidr":
      case "route": {
        return (lane(1)-20)/3
      }
      default: {
        return (lane(1)-10)/2
      }
    }
  }

  build() {
    List({ scroller: this.scroller }) {
      ListItem() {
        if (deviceInfo.sdkApiVersion >= 20) {
          Row() {
            Builders({value: this.item, type: this.type})
              .width('100%')
          }
          .backgroundStyle()
          .LightEffect()
          .overlay(this.LightPoint(),{
            align: Alignment.Center
          })
        }else {
          Row() {
            Builders({value: this.item, type: this.type})
              .width('100%')
          }
          .backgroundStyle()
          .borderColor($r("sys.color.brand"))
          .borderWidth(this.enable?1:0)
          .animation({
            curve: Curve.Ease,
            duration: 300
          })
        }
      }
      .borderRadius(12)
      .swipeAction({
        end: {
          builder: () => { this.rightButton() }
        },
        edgeEffect: SwipeEdgeEffect.Spring
      })
    }
    .borderRadius(12)
    .height(this.comp_height)
    .width('100%')
    .clip(true)
    .onTouch((event) => {
      event.stopPropagation()
    })
  }
}