import { SymbolGlyphModifier } from "@kit.ArkUI"
import { BusinessError, pasteboard } from "@kit.BasicServicesKit"
import Manager from "../Manager"
import { protocolColor, SharedPeer } from "../util/ETConfig"
import { Logger } from "../util/Logger"
import { PermissionUtil } from "../PermissionUtil"
import { abilityAccessCtrl } from "@kit.AbilityKit"
import { EventHelper } from "../util/EventHelper"
import { WebUtil } from "../WebUtil"
import { vibrator } from "@kit.SensorServiceKit"
import { PreferenceUtil } from "../PreferencesUtil"
import { UIType, WindowUtil } from "../WindowUtil"
import { ContextUtil } from "../ContextUtil"
import { lane } from "../util/Conversion"
import { HdsNavigationIconOptions, HdsNavigationMenuItemOptions, IconStyleMode } from "@kit.UIDesignKit"
import { AppManager } from "../AppManager"

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
        AppManager.web.updateSharedPeers()
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
      }
      Toggle({ type: ToggleType.Switch, isOn: AppManager.preference.show_log })
        .selectedColor($r('sys.color.brand'))
        .switchPointColor($r('sys.color.comp_background_list_card'))
        .onChange((isOn: boolean) => {
          AppManager.preference.show_log = isOn
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
            AppManager.permission.requestLocPerm()
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
            AppManager.permission.requestDistributePerm()
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

export function HdsMenuButton(value: ResourceStr, symbol: Resource, callback: () => void): HdsNavigationMenuItemOptions {
  return {
    content: {
      icon: new SymbolGlyphModifier(symbol),
      label: value,
      action: ()=>{
        callback()
      },
      type: IconStyleMode.LARGE
    }
  }
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

@Builder
function gradientText(size: number = 36, text: string | Resource | undefined = 'EasyTier', weight: number | FontWeight | ResourceStr = FontWeight.Bold, angle: string | number | undefined = 225) {
  Stack() {
    Row() {
      Text(text)
        .fontWeight(weight)
        .minFontSize(1)
        .maxFontSize(100)
        .maxLines(1)
        .blendMode(BlendMode.DST_IN, BlendApplyType.OFFSCREEN)
        .clip(false)
        .padding(5)
    }
    .linearGradient({
      colors:[
        ['rgba(255,200,50,1)', 0.3],
        ['rgba(0,230,118,1)', 1]
      ],
      angle: angle
    })
    .blendMode(BlendMode.SRC_OVER, BlendApplyType.OFFSCREEN)
    .justifyContent(FlexAlign.Center)
  }
  .layoutWeight(size)
  .clip(false)
}
