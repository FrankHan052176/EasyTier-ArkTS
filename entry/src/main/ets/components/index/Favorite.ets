import { AppManager } from '../../AppManager'
import { CompTitle } from './Basic'

@Extend(Column)
function comp_bg() {
  .width('100%')
  .height('100%')
  .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
}

@Builder
export function Favorite() {
  Column() {
    CompTitle("收藏实例", 'rgba(255,200,50,1)', ()=>{return -1})
    Column() {
      if (AppManager.data.favoriteInstance !== undefined) {
        Text(AppManager.data.favoriteInstance!)
      }
    }
    .width('100%')
    .layoutWeight(100)
    .padding({left: 10, right: 10, top: 10})
  }
  .comp_bg()
}