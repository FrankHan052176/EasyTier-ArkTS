import { AppManager } from '../AppManager';

@Entry
@ComponentV2
struct StatusBarPage {
  @Local message: string = 'StatusBarExtension Demo';

  aboutToAppear(): void {

  }

  build() {
    RelativeContainer() {
      Text(AppManager.easytier.selected ?? "N/A")
        .id('HelloWorld')
        .fontSize(25)
        .fontWeight(FontWeight.Bold)
        .alignRules({
          center: { anchor: '__container__', align: VerticalAlign.Center },
          middle: { anchor: '__container__', align: HorizontalAlign.Center }
        })
    }
    .height('100%')
    .width('100%')
  }
}