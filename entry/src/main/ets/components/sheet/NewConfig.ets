import { EditableLeftIconType, EditableTitleBar, ExceptionPrompt, LengthMetrics, MarginType,
  uiAppearance } from "@kit.ArkUI";
import { ToolButtonWithPaste } from "../util/ToolButtons";
import { url } from "@kit.ArkTS";
import { Logger } from "../../util/Logger";
import { EventHelper } from "../../util/EventHelper";
import { hdsEffect } from "@kit.UIDesignKit";
import { deviceInfo } from "@kit.BasicServicesKit";
import { Spx2vp } from "../../AppManager";
import { ColumnIlluminatedModifier, RowIlluminatedModifier } from "../../class/modifier/LightModifier";
import { AppManager } from "../../AppManager";

export let config_name: string | undefined

@ComponentV2
export struct NewConfig_Title {
  build() {
    EditableTitleBar({
      leftIconStyle: EditableLeftIconType.Cancel,
      title: '新建实例',
      contentMargin: {
        start: LengthMetrics.vp(0),
        end: LengthMetrics.vp(0),
      },
      onCancel: () => {
        config_name = undefined
        EventHelper.emitterPublish("home_close_sheet")
      },
      onSave: () => {
        if (config_name !== undefined && config_name.length > 0) {
          AppManager.data.newConfig(config_name)
          EventHelper.emitterPublish("home_close_sheet")
        }else {
          EventHelper.emitterPublish("new_config_popup")
        }
      }
    })
  }
}

@Extend(TextInput)
function fieldTextInput(onChange:EditableTextOnChangeCallback, editChange: Callback<boolean, void>) {
  .padding({top:8, bottom: 8, left: 12, right: 12})
  .borderWidth(0)
  .borderRadius(12)
  .onChange(onChange)
  .width('100%')
  .onEditChange(editChange)
}

@ComponentV2
export struct NewConfig_Content {
  @Local column_modifier: ColumnIlluminatedModifier = new ColumnIlluminatedModifier();
  @Local row_modifier: RowIlluminatedModifier = new RowIlluminatedModifier();
  @Local pastePopup: boolean = false
  @Local intensity: number = 0;
  controller: TextInputController = new TextInputController()
  @Local offsetX: number = 0;
  comp_height: number = 0;

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
          height: this.comp_height*2
        }
      }).buildEffect())
      .animation({
        curve: Curve.Ease,
        duration: 300
      })
  }

  aboutToAppear(): void {
    EventHelper.emitterListener("new_config_popup", () => {
      this.pastePopup = true
    })
  }

  build() {
    Column() {
      Column() {
        if (deviceInfo.sdkApiVersion >= 20) {
          TextInput({ placeholder: '请输入实例名称', text: config_name, controller: this.controller })
            .fieldTextInput((value) => {
              config_name = value
            }, (isOn) => {
              this.intensity = isOn?1:0
            })
            .overlay(this.LightPoint(),{
              align: Alignment.Start,
              offset: {
                x: this.offsetX
              }
            })
            .onSecurityStateChange(() => {
              setTimeout(() => {
                this.offsetX = Spx2vp(this.controller.getCaretOffset().x)
              }, 10)
            })
            .onTextSelectionChange(() => {
              setTimeout(() => {
                this.offsetX = Spx2vp(this.controller.getCaretOffset().x)
              }, 10)
            })
            .onContentScroll(() => {
              setTimeout(() => {
                this.offsetX = Spx2vp(this.controller.getCaretOffset().x)
              }, 10)
            })
        }else {
          TextInput({ placeholder: '请输入实例名称', text: config_name, controller: this.controller })
            .fieldTextInput((value) => {
              config_name = value
            }, (isOn) => {
              this.intensity = isOn?1:0
            })
        }
      }
      .width('100%')
      .borderWidth(0)
      .borderRadius(12)
      .attributeModifier(this.column_modifier)
      .bindPopup(this.pastePopup!!, {
        message: '实例名称不能为空',
        placement: Placement.Top,
        autoCancel: true,
        onStateChange: (e)=> {
          if (!e.isVisible) {
            this.pastePopup = false;
          }
        }
      })
      .onAreaChange((_a,b) => {
        this.comp_height = b.height.valueOf() as number
      })

      Row() {
        Row() {
          Text("从剪切板导入")
            .fontSize(16)
            .margin({right: 10})
            .fontColor($r("sys.color.font_primary"))
          ToolButtonWithPaste({
            pasteCallback: (value) => {
              if (value) {
                try {
                  let urlObject = url.URL.parseURL(value);
                  let cfg = urlObject.params.get("cfg")
                  if (cfg) {
                    // TODO 解压缩配置
                  }
                } catch (err) {
                  // TODO Toml转NetworkConfig
                  if (false) {

                  }else {
                    try {
                      this.getUIContext().getPromptAction().showToast({
                        message: "导入失败,请导入标准Toml配置或其他鸿蒙设备分享的链接\n导入文本为：" + value
                      })
                    } catch (e) {
                      Logger.error(`[Index] An unexpected error occurred. Code:${e.code},message:${e.message}`);
                    }
                  }
                }
                EventHelper.emitterPublish("close_sheet", {
                  data: {
                    type: "new"
                  }
                })
              }else {
                try {
                  this.getUIContext().getPromptAction().showToast({
                    message: "导入失败\n剪切板中没有内容！"
                  })
                } catch (e) {
                  Logger.error(`[Index] An unexpected error occurred. Code:${e.code},message:${e.message}`);
                }
              }
            }
          })
        }
        .padding({left: 10, right: 4, top: 4, bottom: 4})
        .borderRadius(24)
        .backgroundColor($r("sys.color.comp_background_tertiary"))
        .attributeModifier(this.row_modifier)
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
        .width('89%')
        .align(Alignment.Start)
        .fontSize(14)
        .fontColor($r("sys.color.font_secondary"))
      Blank()
        .width('100%')
        .height(100)
    }
    .width('90%')
  }
}