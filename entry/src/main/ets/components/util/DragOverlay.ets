import { AppManager } from '../../AppManager'
import { Position } from '../../LayoutUtil'
import { getCompNode } from '../../pages/nodes/CompNode'
import { lane } from '../../util/Conversion'
import { AddFormMenuItem } from '@kit.ArkUI'
import { formBindingData } from '@kit.FormKit'
import { EventHelper } from '../../util/EventHelper'
import { layoutAnimationParm } from '../../pages/nodes/ResizableComponent'
import { Logger } from '../../util/Logger'

@Builder
export function DragOverlayBuilder(type: string | undefined, onlyDrag: boolean = false) {
  DragOverlay({type: type, onlyDrag: onlyDrag})
    .width('100%')
    .height('100%')
}

@ComponentV2
export struct DragOverlay {
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
      x: 10 + size.grid_x * this.GridSize,
      y: 10 + size.grid_y * this.GridSize
    }
  }

  @Computed
  get compSize(): Size {
    let size = AppManager.layout.getCompSize(this.type!)
    return {
      width: lane(size.lane_w),
      height: lane(size.lane_h)
    }
  }

  @Builder
  MyMenu() {
    Menu() {
      AddFormMenuItem(
        {
          bundleName: 'top.frankhan.easytier', // 包名
          abilityName: 'EntryFormAbility', // 模块ability名称
          parameters: {
            'ohos.extra.param.key.form_dimension': 2, // 卡片尺寸，1代表1*2卡片，2代表2*2卡片，3代表2*4卡片，4代表4*4卡片，7代表6*4卡片
            'ohos.extra.param.key.form_name': 'widget', // 卡片名称
            'ohos.extra.param.key.module_name': 'entry' // 卡片所属的模块名称
          },
        },
        this.type!,
        {
          formBindingData: formBindingData.createFormBindingData({type: this.type}),
          callback: (error, formId) => {

          }
        }
      )
    }
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

  build() {
    Stack({alignContent:Alignment.TopStart}) {
      RelativeContainer(){
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
            }
          })
          .onTouch((event) => {
            event.stopPropagation()
          })
      }
      .size(this.compSize)
      .backgroundColor(Color.Transparent)
      .clip(false)
      .offset({
        x: AppManager.layout.desktopPosX + this.compPos.x,
        y: AppManager.layout.desktopPosY + this.compPos.y
      })
    }
    .backgroundColor(Color.Transparent)
    .backdropBlur(this.openMenu?20:0)
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