import { NewConfig_Content, NewConfig_Title } from "./NewConfig"
import { Setting_Sheet, Setting_Title } from "./Settings"

@Builder
export function SheetContent(type: string) {
  if (type === "new") {
    NewConfig_Content()
  }else if (type === "setting") {
    Setting_Sheet()
  }else {
    Text(type)
  }
}

@Builder
export function SheetTitle(type: string) {
  Row() {
    if (type === "new") {
      NewConfig_Title()
    }else if (type === "setting") {
      Setting_Title()
    }else {
      Text(type)
    }
  }.width('100%').height('100%')
}