import Manager from '../Manager'
import { ToolButton, ToolButtonWithPaste } from '../pages/Components'
import { EventHelper } from './EventHelper'

let new_config_name: string = ""
export function cleanNewConfigName() {
  new_config_name = ''
}
@Builder
export function AddSheetTitle() {
  Row() {
    Text("新增实例")
      .fontColor($r("sys.color.font_primary"))
      .fontSize(20)
    ToolButton({
      symbol: $r("sys.symbol.checkmark"),
      bgColor: $r("sys.color.comp_background_emphasize"),
      symbolColor: [$r("sys.color.font_on_primary")]
    })
      .onClick(() => {
        Manager.addConfigByName(new_config_name)
        EventHelper.emitterPublish("sheet_add_config_close")
      })
  }
  .alignItems(VerticalAlign.Center)
  .justifyContent(FlexAlign.SpaceBetween)
  .width('100%')
}
@Builder
export function AddConfig() {
  Column() {
    TextInput({ placeholder: '请输入实例名称', text: new_config_name })
      .showUnderline(true)
      .onChange((value) => {
        new_config_name = value
      })
    Row() {
      Row() {
        Text("从剪切板导入")
          .fontSize(16)
          .margin({right: 10})
          .fontColor($r("sys.color.font_primary"))
        ToolButtonWithPaste({
          pasteCallback: () => {

          }
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

export { ToolButton }
