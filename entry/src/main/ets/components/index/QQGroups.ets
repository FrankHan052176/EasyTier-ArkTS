import { CompTitle } from './Basic'

@Extend(Column)
function comp_bg() {
  .width('100%')
  .height('100%')
  .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
}

@Builder
export function QQGroups() {
  Column() {
    CompTitle("QQ群", '#0052d9', ()=>{return -1})
    Column() {

    }
    .width('100%')
    .layoutWeight(100)
    .padding(10)
    .justifyContent(FlexAlign.Start)
  }
  .comp_bg()
}