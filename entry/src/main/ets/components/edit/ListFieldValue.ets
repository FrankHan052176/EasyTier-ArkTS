import { FieldValue } from "../../class/config/Basic";
import { NetworkConfig } from "../../protobuf/api_manage";
import { Cidr, CidrBuilder, RouteBuilder, setEditValue_Cidr } from "../../class/config/Cidr";
import { hdsEffect } from "@kit.UIDesignKit";
import { uiAppearance } from "@kit.ArkUI";
import { lane } from "../../util/Conversion";
import { deviceInfo } from "@kit.BasicServicesKit";
import { ContentUtil } from "../../ContentUtil";
import { ToolButton } from "../../pages/Components";
import { EventHelper } from "../../util/EventHelper";
import { ListenerBuilder, setEditValue_Url, Url, UrlBuilder } from "../../class/config/Url";
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
    if (this.type === "cidr") {
      CidrBuilder(this.value as Cidr)
    }else if (this.type === "route") {
      RouteBuilder(this.value as Cidr)
    }else if (this.type === "peer") {
      UrlBuilder(this.value as Url)
    }else if (this.type === "listener" || this.type === "mappedListener") {
      ListenerBuilder(this.value as Url)
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
  private scroller: ListScroller = new ListScroller();

  aboutToAppear(): void {
    this.enable = (this.config[ContentUtil.safeFieldName(this.field)] as string[]).indexOf(this.item.toString()) >= 0
    EventHelper.emitterListener("click_edit", () => {
      try {
        this.scroller.closeAllSwipeActions();
      } catch (error) {}
    })
  }

  @Styles
  backgroundStyle() {
    .width('100%')
    .borderRadius(18)
    .padding({left: 12, right: 12, top: 13, bottom: 13})
    .backgroundColor($r("sys.color.comp_background_primary"))
    .clickEffect({
      level: ClickEffectLevel.LIGHT
    })
    .onClick(() => {
      this.click()
    })
    .clip(true)
  }

  click() {
    const pos = (this.config[ContentUtil.safeFieldName(this.field)] as string[]).indexOf(this.item.toString())
    if (pos >= 0) {
      (this.config[ContentUtil.safeFieldName(this.field)] as string[]).splice(pos, 1)
    }else {
      (this.config[ContentUtil.safeFieldName(this.field)] as string[]).push(this.item.toString())
    }
    this.enable = !this.enable
  }

  build() {
    Row() {
      Builders({value: this.item, type: this.type})
        .width('100%')
    }
    .backgroundStyle()
    .width('100%')
    .clip(true)
    .onTouch((event) => {
      event.stopPropagation()
    })
  }
}