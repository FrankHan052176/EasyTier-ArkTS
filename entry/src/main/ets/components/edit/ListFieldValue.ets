import { NetworkConfig } from '../../protobuf/api_manage';
import { Cidr, CidrBuilder, RouteBuilder } from '../../class/config/Cidr';
import { EventHelper } from '../../util/EventHelper';
import { ListenerBuilder, Url, UrlBuilder } from '../../class/config/Url';
import { IP, IPBuilder } from '../../class/config/IP';
import { NetworkName, NetworkNameBuilder } from '../../class/config/NetworkName';
import { PortForward, PortForwardBuilder } from '../../class/config/PortForward';
import { FieldValue } from '../../class/config/Basic';

@ComponentV2
struct Builders {
  @Param @Require value: FieldValue
  @Param @Require type: string

  build() {
    if (this.type === "cidr") {
      CidrBuilder(this.value as Cidr)
    } else if (this.type === "route") {
      RouteBuilder(this.value as Cidr)
    } else if (this.type === "peer") {
      UrlBuilder(this.value as Url)
    } else if (this.type === "listener" || this.type === "mapped_listener") {
      ListenerBuilder(this.value as Url)
    } else if (this.type === "ip") {
      IPBuilder(this.value as IP)
    } else if (this.type === "network_name") {
      NetworkNameBuilder(this.value as NetworkName)
    } else if (this.type === "port_forward") {
      PortForwardBuilder(this.value as PortForward)
    }
  }
}

@ComponentV2
export struct ListFieldValue {
  @Consumer("config") config: NetworkConfig | null = null;
  @Param @Require field: string;
  @Param @Require type: string;
  @Param @Require value: FieldValue;
  private scroller: ListScroller = new ListScroller();

  aboutToAppear(): void {
    EventHelper.emitterListener("click_edit", () => {
      try {
        this.scroller.closeAllSwipeActions();
      } catch (error) {
      }
    })
  }

  @Styles
  backgroundStyle() {
    .width('100%')
    .borderRadius(18)
    .padding({
      left: 12,
      right: 12,
      top: 13,
      bottom: 13
    })
    .backgroundColor($r("sys.color.comp_background_primary"))
  }

  build() {
    Row() {
      Builders({ value: this.value, type: this.type })
        .width('100%')
    }
    .backgroundStyle()
    .width('100%')
    .onTouch((event) => {
      event.stopPropagation()
    })
  }
}