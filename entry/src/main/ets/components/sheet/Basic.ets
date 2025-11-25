import { NewConfig_Content, NewConfig_Title } from "./NewConfig"

@Builder
export function SheetContent(type: string) {
  if (type === "new") {
    NewConfig_Content()
  }else if (type === "setting") {

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

    }else {
      Text(type)
    }
  }.width('100%').height('100%')
}