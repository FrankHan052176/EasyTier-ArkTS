import { AppManager } from "../../AppManager";
import { CompSize } from "../../LayoutUtil";
import { lane } from "../../util/Conversion";
import { Logger } from "../../util/Logger";
import { getCompNode } from "./CompNode";

@ComponentV2
export struct DesktopLayout {
  @Computed
  get GridSize() {
    return lane(1) + 10
  }

  @Computed
  get CompSizes() {
    return AppManager.layout.comp_sequence.map((value) => {
      return AppManager.layout.getCompSize(value)
    })
  }

  @Computed
  get LayoutHeight() {
    return (AppManager.layout.MaxHeight+1)*lane(1)+(AppManager.layout.MaxHeight+1)*10
  }

  build() {
    Stack({alignContent: Alignment.TopStart}) {
      ForEach(this.CompSizes, (size:CompSize) => {
        if (!size.isOnOverlay) {
          NodeContainer(getCompNode(size.type))
            .offset({
              x: size.grid_x * this.GridSize,
              y: size.grid_y * this.GridSize
            })
        }
      })
    }
    .width("100%")
    .height(this.LayoutHeight)
    .padding({top: 15, left: 15})
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .onAreaChange((a,b) => {
      AppManager.layout.desktopPosX = b.globalPosition.x!.valueOf() as number
      AppManager.layout.desktopPosY = b.globalPosition.y!.valueOf() as number
      AppManager.layout.desktopWidth = b.width.valueOf() as number
      AppManager.layout.desktopHeight = b.height.valueOf() as number
    })
  }
}