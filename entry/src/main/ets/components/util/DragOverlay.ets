import { AppManager } from '../../AppManager'
import { CompSize, Position } from '../../LayoutUtil'
import { getCompNode } from '../../pages/nodes/CompNode'
import { lane } from '../../util/Conversion'
import { AddFormMenuItem } from '@kit.ArkUI'
import { formBindingData } from '@kit.FormKit'
import { EventHelper } from '../../util/EventHelper'
import { layoutAnimationParm } from '../../pages/nodes/ResizableComponent'

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
          formBindingData: formBindingData.createFormBindingData({ type: this.type }),
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
    Stack({ alignContent: Alignment.TopStart }) {
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
        .onTouch((event) => {
          event.stopPropagation()
        })
        .offset({
          x: this.comp_pos!.x,
          y: this.comp_pos!.y
        })
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