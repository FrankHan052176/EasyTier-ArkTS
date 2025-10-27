import { SymbolGlyphModifier } from "@kit.ArkUI"
import { BusinessError, pasteboard } from "@kit.BasicServicesKit"
import Manager, { UIType } from "../Manager"
import { protocolColor, SharedPeer } from "../util/config/ETConfig"
import Logger from "../util/Logger"
import {
  requestDistributePerm, requestLocPerm } from "../util/Permission"
import { abilityAccessCtrl, Context } from "@kit.AbilityKit"
import { laneWidth, laneHeight } from "../util/Conversion"
import EventHelper from "../util/EventHelper"
import { CompSize } from "./nodes/AutoSortContainer"
import { updateSharedPeers } from "../util/info/WebInfo"
import { vibrator } from "@kit.SensorServiceKit"

interface color {
  r: number
  g: number
  b: number
}
interface colorStop {
  pos: number
  color: color
}
function getLoadColor(percentage: number): string {
  const p = Math.max(0, Math.min(100, percentage)) / 100;

  const colorStops: colorStop[] = [
    { pos: 0.0, color: { r: 100, g: 187, b: 92 } },   // #64bb5c (0%)
    { pos: 0.3, color: { r: 147, g: 196, b: 70 } },   // 浅绿黄
    { pos: 0.5, color: { r: 194, g: 204, b: 48 } },   // 黄绿
    { pos: 0.7, color: { r: 225, g: 160, b: 30 } },   // 橙黄
    { pos: 1.0, color: { r: 232, g: 64, b: 38 } }     // #e84026 (100%)
  ];

  // 找到当前百分比所在区间
  let startStop = colorStops[0];
  let endStop = colorStops[colorStops.length - 1];

  for (let i = 0; i < colorStops.length - 1; i++) {
    if (p >= colorStops[i].pos && p <= colorStops[i + 1].pos) {
      startStop = colorStops[i];
      endStop = colorStops[i + 1];
      break;
    }
  }

  // 计算插值比例
  const factor = (p - startStop.pos) / (endStop.pos - startStop.pos);
  const r = Math.round(startStop.color.r + (endStop.color.r - startStop.color.r) * factor);
  const g = Math.round(startStop.color.g + (endStop.color.g - startStop.color.g) * factor);
  const b = Math.round(startStop.color.b + (endStop.color.b - startStop.color.b) * factor);

  return `#${r.toString(16)}${g.toString(16)}${b.toString(16)}`;
}

@Builder
export function SharedPeersSheet() {
  List({space: 10}) {
    if (Manager.sharedPeers.size > 0) {
      LazyForEach(Manager.sharedPeers, (value: SharedPeer) => {
        ListItem() {
          Stack({alignContent: Alignment.TopStart}) {
            Row() {
              Text(value._protocol.toUpperCase())
                .fontColor($r("sys.color.font_on_primary"))
                .fontSize(12)
                .borderRadius(6)
                .width(40)
                .backgroundColor(protocolColor(value._protocol))
                .padding({top: 3, bottom: 3, right: 5, left: 5})
                .textAlign(TextAlign.Center)
            }
            .alignItems(VerticalAlign.Center)
            .justifyContent(FlexAlign.End)
            .width('100%')
            .offset({
              x: 6,
              y: -6
            })
            Row() {
              Progress({
                value: value.usage_percentage, total: 100, type: ProgressType.Linear,
              })
                .width('100%')
                .color(getLoadColor(value.usage_percentage))
                .offset({
                  y: 6
                })
            }
            .height('100%')
            .width('100%')
            .justifyContent(FlexAlign.Center)
            .alignItems(VerticalAlign.Bottom)
            Row() {
              Text(value.name)
                .fontSize(12)
                .maxLines(2)
                .width(135)
              Column() {
                Text(value.allow_relay?"可转发":"禁转发")
                  .fontColor($r("sys.color.font_on_primary"))
                  .fontSize(12)
                  .borderRadius(6)
                  .width(50)
                  .backgroundColor(value.allow_relay?$r("sys.color.confirm"):$r("sys.color.warning"))
                  .padding({top: 3, bottom: 3, right: 5, left: 5})
                  .textAlign(TextAlign.Center)
                Text(value.version)
                  .fontColor($r("sys.color.font_on_primary"))
                  .fontSize(12)
                  .borderRadius(6)
                  .width(50)
                  .backgroundColor($r("sys.color.comp_background_emphasize"))
                  .padding({top: 3, bottom: 3, right: 5, left: 5})
                  .textAlign(TextAlign.Center)
              }
              .margin({left: 5})
              .alignItems(HorizontalAlign.Center)
              .justifyContent(FlexAlign.SpaceBetween)
              .height('100%')
              Row() {
                Text(""+value.current_connections+"/"+value.max_connections)
                  .margin({bottom: 5})
                  .width(68)
                  .textAlign(TextAlign.End)
                Checkbox()
                  .select(Manager.peers.has(value))
                  .selectedColor($r("sys.color.comp_background_emphasize"))
                  .shape(CheckBoxShape.CIRCLE)
                  .onChange((isOn: boolean) => {
                    if (isOn) {
                      Manager.peers.add(value)
                    }else {
                      Manager.peers.delete(value)
                      Manager.configs.forEach((cfg) => {
                        cfg.peer.delete(value)
                      })
                    }
                  })
                  .clickEffect({
                    level: ClickEffectLevel.LIGHT,
                    scale: 1.0
                  })
                  .margin({top: 20})
                  .zIndex(2)
              }
              .height('100%')
              .alignItems(VerticalAlign.Center)
              .justifyContent(FlexAlign.SpaceBetween)
              .layoutWeight(100)
              .margin({left: 5})
            }
            .width('100%')
            .height('100%')
            .alignItems(VerticalAlign.Center)
            .justifyContent(FlexAlign.Start)
          }
          .width("100%")
          .height(60)
          .borderRadius(10)
          .backgroundColor($r("sys.color.background_secondary"))
          .padding(10)
        }
        .clickEffect({
          level: ClickEffectLevel.LIGHT
        })
      })
      ListItem() {
      }
      .width('100%')
      .height(50)
    }else {
      ListItem() {
        Text("无社区共享节点")
          .fontSize(14)
          .width("100%")
      }
    }
  }
  .alignListItem(ListItemAlign.Start)
  .padding({left: 10, right: 10})
  .width("100%")
  .height("100%")
  .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.START, SafeAreaEdge.BOTTOM])
}

@Builder
export function SharedPeersTitle() {
  Row() {
    Text("社区共享节点")
      .fontColor($r("sys.color.font_primary"))
      .fontSize(20)
    ToolButton({
      symbol: $r("sys.symbol.arrow_clockwise")
    })
      .margin({right: 10})
      .onClick(() => {
        updateSharedPeers()
      })
  }
  .alignItems(VerticalAlign.Center)
  .justifyContent(FlexAlign.SpaceBetween)
  .width('100%')
}

@Builder
export function AddSheet(pastCallback: (value:string)=>void, textUpdate: (value:string)=>void, text: string) {
  Column() {
    TextInput({ placeholder: '请输入实例名称', text: text })
      .showUnderline(true)
      .onChange(textUpdate)
    Row() {
      Row() {
        Text("从剪切板导入")
          .fontSize(16)
          .margin({right: 10})
          .fontColor($r("sys.color.font_primary"))
        ToolButtonWithPaste({
          pasteCallback: pastCallback
        })
      }
      .padding({left: 10, right: 4, top: 4, bottom: 4})
      .borderRadius(24)
      .backgroundColor($r("sys.color.comp_background_tertiary"))
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .justifyContent(FlexAlign.End)
    .margin({top: 10, bottom: 10})
    Text(`
实例名称用于用户区分实例，可同名。
如：测试、FrankHan、EasyTier、🚀出发去火星。
从剪切板导入可导入从其他平台复制的配置，无法与HomoTier的配置兼容。
      `)
      .width('100%')
      .align(Alignment.Start)
      .fontSize(14)
      .fontColor($r("sys.color.font_secondary"))
    Blank()
      .width('100%')
      .height(100)
  }
  .width('80%')
}

@Builder
export function AddSheetTitle(confirmCallback: ()=>void) {
  Row() {
    Text("新增实例")
      .fontColor($r("sys.color.font_primary"))
      .fontSize(20)
    ToolButton({
      symbol: $r("sys.symbol.checkmark"),
      bgColor: $r("sys.color.comp_background_emphasize"),
      symbolColor: [$r("sys.color.font_on_primary")]
    })
      .onClick(confirmCallback)
  }
  .alignItems(VerticalAlign.Center)
  .justifyContent(FlexAlign.SpaceBetween)
  .width('100%')
}

@Builder
export function settingSheet() {
  Column() {
    Row() {
      Row() {
        SymbolGlyph($r("sys.symbol.trash"))
          .fontColor([$r("sys.color.warning")])
          .fontSize(16)
          .margin({right: 5})
        Text("重置数据")
          .fontColor($r("sys.color.warning"))
          .fontSize(16)
      }
      Button('重置', { type: ButtonType.Normal, buttonStyle: ButtonStyleMode.EMPHASIZED, role: ButtonRole.ERROR})
        .borderRadius(13)
        .onClick(() => {
          Manager.clearDB()
          Manager.configs.clear()
          Manager.peers.clear()
          Manager.network_identities.clear()
          Manager.listeners.clear()
          Manager.routes.clear()
          Manager.cidrs.clear()
          Manager.exit_nodes.clear()
          Manager.whitelist.clear()
        })
    }
    .height(49)
    .borderRadius(18)
    .alignItems(VerticalAlign.Center)
    .justifyContent(FlexAlign.SpaceBetween)
    .width('100%')
    .backgroundColor($r("sys.color.background_secondary"))
    .padding({left: 10, right: 5, top: 5, bottom: 5})
    .margin({bottom: 10})
    Row() {
      Row() {
        SymbolGlyph($r("sys.symbol.exclamationmark_message_middle_bottom"))
          .fontColor([$r("sys.color.font_primary")])
          .fontSize(16)
          .margin({right: 5})
        Text("收集EasyTier日志")
          .fontColor($r("sys.color.font_primary"))
          .fontSize(16)
          .margin({right: 5})
        if (Manager.preference_log != Manager.show_log) {
          Text("重启后生效")
            .fontColor($r("sys.color.font_secondary"))
            .fontSize(14)
        }
      }
      Toggle({ type: ToggleType.Switch, isOn: Manager.preference_log })
        .selectedColor($r('sys.color.brand'))
        .switchPointColor($r('sys.color.comp_background_list_card'))
        .onChange((isOn: boolean) => {
          try {
            Manager.Preferences!.putSync("show_log", isOn)
          } catch (e) {
            Logger.error(`[Components] An unexpected error occurred. Code:${e.code},message:${e.message}`);
          }
          try {
            Manager.Preferences!.flushSync()
          } catch (e) {
            Logger.error(`[Components] An unexpected error occurred. Code:${e.code},message:${e.message}`);
          }
        })
        .height(29)
        .width(52)
    }
    .height(49)
    .borderRadius(18)
    .alignItems(VerticalAlign.Center)
    .justifyContent(FlexAlign.SpaceBetween)
    .width('100%')
    .backgroundColor($r("sys.color.background_secondary"))
    .padding(10)
    .margin({bottom: 10})
    Row() {
      Row() {
        SymbolGlyph($r("sys.symbol.local_and_rectangle"))
          .fontColor([$r("sys.color.font_primary")])
          .fontSize(16)
          .margin({right: 5})
        Text("定位权限")
          .fontColor($r("sys.color.font_primary"))
          .fontSize(16)
      }
      if (Manager.locPerm == abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED) {
        Text("已授权")
          .fontColor($r("sys.color.font_primary"))
          .fontSize(16)
          .margin({right: 5})
      }else {
        Button('授权', { type: ButtonType.Normal, buttonStyle: ButtonStyleMode.EMPHASIZED, role: ButtonRole.NORMAL})
          .borderRadius(13)
          .onClick(() => {
            requestLocPerm(Manager.uiContext!.getHostContext()!)
          })
      }
    }
    .height(49)
    .borderRadius(18)
    .alignItems(VerticalAlign.Center)
    .justifyContent(FlexAlign.SpaceBetween)
    .width('100%')
    .backgroundColor($r("sys.color.background_secondary"))
    .padding({left: 10, right: 5, top: 5, bottom: 5})
    .margin({bottom: 10})
    Row() {
      Row() {
        SymbolGlyph($r("sys.symbol.protein"))
          .fontColor([$r("sys.color.font_primary")])
          .fontSize(16)
          .margin({right: 5})
        Text("分布式权限")
          .fontColor($r("sys.color.font_primary"))
          .fontSize(16)
      }
      if (Manager.distributePerm == abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED) {
        Text("已授权")
          .fontColor($r("sys.color.font_primary"))
          .fontSize(16)
          .margin({right: 5})
      }else {
        Button('授权', { type: ButtonType.Normal, buttonStyle: ButtonStyleMode.EMPHASIZED, role: ButtonRole.NORMAL})
          .borderRadius(13)
          .onClick(() => {
            requestDistributePerm(Manager.uiContext!.getHostContext()!)
          })
      }
    }
    .height(49)
    .borderRadius(18)
    .alignItems(VerticalAlign.Center)
    .justifyContent(FlexAlign.SpaceBetween)
    .width('100%')
    .backgroundColor($r("sys.color.background_secondary"))
    .padding({left: 10, right: 5, top: 5, bottom: 5})
    .margin({bottom: 10})
  }
  .width('100%')
  .padding({left: 10, right: 10})
}

export function MenuButton(value: string | Resource, symbol: Resource, callback: () => void): NavigationMenuItem {
  return {'value': value, 'symbolIcon': new SymbolGlyphModifier(symbol), 'action': ()=> {
    callback()
  }}
}

@ComponentV2
export struct ToolButton {
  @Param @Require symbol: Resource
  @Param buttonSize: number = 40
  @Param symbolScale: number = 0.6
  @Param bgColor: ResourceColor = $r("sys.color.comp_background_tertiary")
  @Param symbolColor: Array<ResourceColor> = [$r("sys.color.font_primary")]
  build() {
    Button({ type: ButtonType.Circle }) {
      SymbolGlyph(this.symbol)
        .fontColor(this.symbolColor)
        .fontSize(this.buttonSize*this.symbolScale)
        .animation({
          curve: Curve.EaseIn,
          duration: 300
        })
    }
    .width(this.buttonSize).height(this.buttonSize)
    .buttonStyle(ButtonStyleMode.NORMAL)
    .backgroundColor(this.bgColor)
    .clickEffect({
      level: ClickEffectLevel.LIGHT,
      scale: 0.8
    })
    .animation({
      curve: Curve.EaseIn,
      duration: 300
    })
  }
}

@ComponentV2
export struct ToolButtonWithText {
  @Param @Require symbol: Resource
  @Param @Require text: string
  @Param bgColor: ResourceColor = $r("sys.color.comp_background_tertiary")
  @Param textColor: ResourceColor = $r("sys.color.font_primary")
  @Param symbolColor: Array<ResourceColor> = [$r("sys.color.font_primary")]
  @Param symbolSize: number = 24
  @Param textSize: number = 18

  build() {
    Button({ type: ButtonType.Capsule }) {
      Row() {
        SymbolGlyph(this.symbol)
          .fontColor(this.symbolColor)
          .fontSize(this.symbolSize)
        Text(this.text)
          .fontColor(this.textColor)
          .fontSize(this.textSize)
      }
      .justifyContent(FlexAlign.SpaceAround)
    }
    .padding({left: 10, right: 10})
    .height(this.symbolSize/6*10)
    .buttonStyle(ButtonStyleMode.NORMAL)
    .backgroundColor(this.bgColor)
    .clickEffect({
      level: ClickEffectLevel.LIGHT,
      scale: 0.8
    })
  }
}

@ComponentV2
export struct ToolButtonWithPaste {
  @Param pasteCallback: (value: string) => void = () => {}
  build() {
    PasteButton({
      buttonType: ButtonType.Circle,
      text: undefined
    })
      .padding({left: 10, right: 10})
      .height(40)
      .onClick((_event, result) => {
        if (PasteButtonOnClickResult.SUCCESS === result) {
          pasteboard.getSystemPasteboard().getData((err: BusinessError, pasteData: pasteboard.PasteData) => {
            if (err) {
              console.error(`Failed to get paste data. Code is ${err.code}, message is ${err.message}`);
              return;
            }
            this.pasteCallback(pasteData.getPrimaryText())
          });
        }else {
          Logger.debug("failed get perm")
        }
      })
  }
}

const animationParm: AnimateParam = {
  duration: 200,
  curve: Curve.Friction
}

@ComponentV2
struct ResizeBall {
  @Param @Require addDirection: PanDirection
  @Param @Require isResize: boolean
  @Param @Require isAddable: () => boolean
  @Param @Require isDeletable: () => boolean
  @Param @Require lane: number
  @Param @Require length: number
  @Event $lane: (val: number) => void = (val: number) => {}
  @Param @Require extra: number
  @Event $extra: (val: number) => void = (val: number) => {}
  @Local fingerOffset: number = 0
  @Local disable_a: boolean = false
  @Local disable_d: boolean = false
  @BuilderParam content: ()=>void

  @Computed
  get isHorizontal() {
    return this.addDirection == PanDirection.Left || this.addDirection == PanDirection.Right
  }

  getFixScale(): number {
    return (this.addDirection == PanDirection.Left || this.addDirection == PanDirection.Up)?-1:1
  }

  getOffset(event: GestureEvent): number {
    if (this.isHorizontal) {
      return (event.offsetX - this.fingerOffset)*this.getFixScale()
    }else {
      return (event.offsetY - this.fingerOffset)*this.getFixScale()
    }
  }

  getRawOffset(event: GestureEvent): number {
    return this.isHorizontal?event.offsetX:event.offsetY
  }

  getLane(lane: number = this.lane): number {
    if (this.isHorizontal) {
      return laneWidth(lane)
    }else {
      return laneHeight(lane)
    }
  }

  canExtra(offset: number): boolean {
    return offset>0?this.isAddable() && this.getNextLane() > this.lane:this.isDeletable() && this.getPreLane() < this.lane
  }

  extraLane(offset: number) {
    if (offset>0) {
      this.$lane(this.getNextLane())
    }else {
      this.$lane(this.getPreLane())
    }
  }

  getNextLane(): number {
    if (this.isHorizontal) {
      switch (Manager.uiType) {
        case UIType.Column_1: {
          return Math.min(2, this.lane+1)
        }
        case UIType.Column_2: {
          return Math.min(4, this.lane+1)
        }
        case UIType.Column_3: {
          return Math.min(6, this.lane+1)
        }
      }
    }else {
      return Math.min(4, this.lane+1)
    }
  }

  getPreLane(): number {
    return Math.max(1, this.lane-1)
  }

  build() {
    Row() {
      Stack() {
        Circle({ width: 18, height: 18 })
          .fill("#3A0a59f7")
        Circle({ width: 8, height: 8 })
          .fill($r("sys.color.brand"))
      }
    }
    .alignItems(VerticalAlign.Center)
    .justifyContent(FlexAlign.Center)
    .width(!this.isHorizontal?this.length-36:18)
    .height(this.isHorizontal?this.length-36:18)
    .gesture(PanGesture({ direction: this.isHorizontal?PanDirection.Horizontal:PanDirection.Vertical, fingers: 1 })
      .onActionUpdate((event) => {
        animateToImmediately(animationParm, () => {
          let offset = this.getOffset(event)
          if ((!this.disable_a && offset >= 0) || (!this.disable_d && offset < 0)) {
            this.disable_a = false
            this.disable_d = false
            if (Math.abs(offset) >= 30 && !this.canExtra(offset)) {
              this.$extra(0)
              if (offset < 0) {
                this.disable_d = true
              }else {
                this.disable_a = true
              }
            }else if (this.canExtra(offset) && (offset-10 >= this.getLane(1)*0.7 || offset+10 <= this.getLane(1)*-0.5)) {
              this.fingerOffset = this.getRawOffset(event)
              this.extraLane(offset)
            }else {
              this.$extra(offset)
            }
          }else {
            this.fingerOffset = this.getRawOffset(event)
          }
        })
      })
      .onActionEnd(() => {
        animateToImmediately(animationParm, () => {
          this.$extra(0)
          this.fingerOffset = 0
          this.disable_a = false
          this.disable_d = false
        })
      }))
    .hitTestBehavior(this.isResize ? HitTestMode.Block : HitTestMode.Default)
  }
}

@ComponentV2
export struct ResizableComponent {
  @Param @Require comp_type: string
  @Local lane_w: number = 1
  @Local lane_h: number = 1
  @Local offset_l: number = 0
  @Local offset_r: number = 0
  @Local offset_u: number = 0
  @Local offset_d: number = 0
  @Local isResize: boolean = false
  @BuilderParam content: ()=>void
  @Local timer: number = -1
  @Local pan_offset_x: number = 0
  @Local pan_offset_y: number = 0

  @Monitor("lane_w", "lane_h", "offset_l", "offset_r", "offset_u", "offset_d")
  onStrChange(monitor: IMonitor) {

  }

  @Computed
  get offset_w() {
    return this.offset_l + this.offset_r
  }
  @Computed
  get offset_h() {
    return this.offset_u + this.offset_d
  }

  aboutToAppear(): void {
    EventHelper.emitterListener("resize_off", () => {
      animateToImmediately(animationParm, () => {
        this.isResize = false
      })
    })
  }

  build() {
    Stack({alignContent: Alignment.Center}) {
      this.content()
      if (this.isResize) {
        ResizeBall({
          addDirection: PanDirection.Left,
          extra: this.offset_l!!,
          isAddable: ()=>{return false},
          isDeletable: ()=>{return true},
          isResize: this.isResize,
          lane: this.lane_h!!,
          length: laneHeight(this.lane_h) + this.offset_h
        })
          .position({
            x: -8,
            y: 18
          })
        ResizeBall({
          addDirection: PanDirection.Up,
          extra: this.offset_u!!,
          isAddable: ()=>{return false},
          isDeletable: ()=>{return true},
          isResize: this.isResize,
          lane: this.lane_h!!,
          length: laneWidth(this.lane_w) + this.offset_w
        })
          .position({
            x: 18,
            y: -8
          })
        ResizeBall({
          addDirection: PanDirection.Down,
          extra: this.offset_d!!,
          isAddable: ()=>{return true},
          isDeletable: ()=>{return true},
          isResize: this.isResize,
          lane: this.lane_h!!,
          length: laneWidth(this.lane_w) + this.offset_w
        })
          .position({
            x: 18,
            y: laneHeight(this.lane_h) + this.offset_d + this.offset_u -10
          })
        ResizeBall({
          addDirection: PanDirection.Right,
          extra: this.offset_r!!,
          isAddable: ()=>{return true},
          isDeletable: ()=>{return true},
          isResize: this.isResize,
          lane: this.lane_w!!,
          length: laneHeight(this.lane_h) + this.offset_h
        })
          .position({
            x: laneWidth(this.lane_w) + this.offset_r + this.offset_l -10,
            y: 18
          })
      }
    }
    .gesture(GestureGroup(GestureMode.Sequence,LongPressGesture({ repeat: false, fingers: 1 })
      .onAction((event: GestureEvent|undefined) => {
        if(event && !this.isResize) {
          vibrator.startVibration({
            type: 'time',
            duration: 1,
          }, {
            id: 0,
            usage: 'touch'
          }, () => {})
          animateToImmediately(animationParm, () => {
            this.isResize = true
          })
        }
      }),
      PanGesture({direction: PanDirection.All, fingers: 1})
      .onActionStart((event) => {
        if(event) {
          animateToImmediately(animationParm, () => {
            this.isResize = false
          })
        }
      }).onActionUpdate((event) => {
        if(event) {
          this.pan_offset_x = event.offsetX
          this.pan_offset_y = event.offsetY
        }
      }).onActionEnd((event) => {
        if (event) {
          animateToImmediately(animationParm, () => {
            this.isResize = true
            this.pan_offset_x = 0
            this.pan_offset_y = 0
          })
        }
      }))
    )
    .borderWidth(this.isResize?2:0)
    .borderColor($r("sys.color.brand"))
    .borderRadius(34)
    .width(laneWidth(this.lane_w) + this.offset_w)
    .height(laneHeight(this.lane_h) + this.offset_h)
    .position({
      x: -this.offset_l + this.pan_offset_x,
      y: -this.offset_u + this.pan_offset_y
    })
  }
}
