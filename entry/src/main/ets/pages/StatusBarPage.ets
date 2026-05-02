import { AppManager } from '../AppManager';

@Entry
@Component
struct StatusBarPage {

  build() {
    Column() {
      Text(AppManager.uiState.selected ?? "未选择实例")
        .id('HelloWorld')
        .fontSize(25)
        .fontWeight(FontWeight.Bold)
      Text(AppManager.uiState.favorite ?? "未收藏实例")
        .id('HelloWorld')
        .fontSize(25)
        .fontWeight(FontWeight.Bold)
      Text(""+AppManager.easytier.getAllConfigIds().length)
        .id('HelloWorld')
        .fontSize(25)
        .fontWeight(FontWeight.Bold)
    }
    .height('100%')
    .width('100%')
  }
}
