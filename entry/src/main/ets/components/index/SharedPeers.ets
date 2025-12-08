import { CompTitle } from './Basic'

@Extend(Column)
function comp_bg() {
  .width('100%')
  .height('100%')
  .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
}

@Builder
export function SharedPeers() {
  Column() {
    CompTitle("社区共享", 'rgba(0,230,118,1)', () => {
      return -1
    })
    Column() {
      Text("为了 EasyTier和MC 社区的长远发展，我们会尽快完成完全合规化运营，在此之前 社区共享节点 会临时关闭，在不久的将来，他会与各位重新见面。")
        .fontSize(12)
        .width('100%')
    }
    .width('100%')
    .layoutWeight(100)
    .padding(10)
    .justifyContent(FlexAlign.Start)
  }
  .comp_bg()
}