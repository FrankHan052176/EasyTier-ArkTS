import { ConfigField, ContentUtil } from '../../ContentUtil'
import { NetworkConfig } from '../../protobuf/api_manage'
import { FieldEdit } from './FieldEdit'

@ComponentV2
export struct EditPage {
  @Param @Require config: NetworkConfig

  build() {
    List({space: 10}) {
      ListItem()
        .width('100%')
        .height(1)
      ForEach(ContentUtil.fieldList, (field: ConfigField) => {
        ListItem(){
          FieldEdit({config: this.config, field: field})
            .width('100%')
        }
      })
    }
    .scrollBar(BarState.Off)
    .chainAnimation(true)
    .scrollSnapAlign(ScrollSnapAlign.START)
    .padding({left: 20, right: 20})
    .width('100%')
    .height('100%')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}