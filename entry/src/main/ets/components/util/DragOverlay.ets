import { AppManager } from '../../AppManager'
import { CompSize, Position } from '../../LayoutUtil'
import { getCompNode } from '../../pages/nodes/CompNode'
import { lane } from '../../util/Conversion'
import { EventHelper } from '../../util/EventHelper'
import { layoutAnimationParm } from '../../pages/nodes/ResizableComponent'
import { symbolWithSize } from '../../pages/hmrouter/HomePage'
import { Want } from '@kit.AbilityKit'
import { formProvider } from '@kit.FormKit'
import { deviceInfo } from '@kit.BasicServicesKit'
import { Logger } from '../../util/Logger'

@Builder
export function DragOverlayBuilder(type: string | undefined, onlyDrag: boolean = false, compPos: Position | undefined) {
  DragOverlay({ type: type, onlyDrag: onlyDrag, comp_pos: compPos })
    .width('100%')
    .height('100%')
}

@ComponentV2
export struct DragOverlay {
  @Param @Require comp_pos: Position | undefined
  @Param @Require type: string | undefined
  @Param @Require onlyDrag: boolean
  @Local openMenu: boolean = false

  @Computed
  get GridSize() {
    return lane(1) + 10
  }

  @Computed
  get compPos(): Position {
    let size = AppManager.layout.getCompSize(this.type!)
    return {
      x: 15 + size.grid_x * this.GridSize,
      y: 15 + size.grid_y * this.GridSize
    }
  }

  @Computed
  get compSize(): CompSize {
    return AppManager.layout.getCompSize(this.type!)
  }

  aboutToAppear(): void {
    EventHelper.emitterListener("drag_overlay_move", () => {
      this.openMenu = false
    })
    if (!this.onlyDrag) {
      setTimeout(() => {
        animateToImmediately(layoutAnimationParm, () => {
          this.openMenu = true
        })
      }, 1)
    }
  }

  aboutToDisappear(): void {
    EventHelper.emitterOff("drag_overlay_move")
  }

  @Builder
  MyMenu() {
    Menu() {
      if (this.type === "Favorite") {
        MenuItem({
          symbolStartIcon: symbolWithSize($r('sys.symbol.plus_square'), 24),
          content: "添加到桌面"
        })
          .onClick(() => {
            const want: Want = {
              bundleName: "top.frankhan.easytier",
              abilityName: 'EntryFormAbility',
              parameters: {
                'ohos.extra.param.key.form_dimension': 1,
                'ohos.extra.param.key.form_name': this.type!.toLowerCase()+'_widget',
                'ohos.extra.param.key.module_name': 'entry'
              },
            };
            if (deviceInfo.sdkApiVersion >= 18) {
              try {
                formProvider.openFormManager(want)
              } catch (error) {
                Logger.error(JSON.stringify(error), "DragOverlay")
              }
            }
          })
      }
      MenuItem({
        symbolStartIcon: symbolWithSize($r('sys.symbol.eye_slash'), 24),
        content: "隐藏组件"
      })
        .onClick(() => {
          EventHelper.emitterPublish("hide_comp_and_overlay_off")
        })
    }
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      if (AppManager.layout.comp_sequence.includes(this.compSize.type)) {
        NodeContainer(getCompNode(this.type))
          .bindContextMenu(this.openMenu, this.MyMenu, {
            placement: Placement.TopRight,
            onDisappear: () => {
              animateToImmediately({
                duration: 300,
                curve: Curve.Friction
              }, () => {
                this.openMenu = false
              })
              if (!this.compSize.isDragging) {
                EventHelper.emitterPublish("drag_overlay_off")
              }
            }
          })
          .offset({
            x: this.comp_pos!.x,
            y: this.comp_pos!.y
          })
      }
    }
    .backgroundColor(Color.Transparent)
    .backdropBlur(this.openMenu ? 20 : 0)
    .width('100%')
    .height('100%')
    .onTouch((event) => {
      if (event.type === TouchType.Down) {
        EventHelper.emitterPublish("drag_overlay_cancel")
        animateToImmediately({
          duration: 300,
          curve: Curve.Friction
        }, () => {
          this.openMenu = false
        })
        setTimeout(() => {
          EventHelper.emitterPublish("drag_overlay_off")
        }, 300)
      }
    })
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}