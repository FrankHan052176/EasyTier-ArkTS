import { promptAction } from '@kit.ArkUI'

let toastUiContext: UIContext | undefined = undefined

export function initToast(uiContext: UIContext): void {
  toastUiContext = uiContext
}

export function sendToast(text: ResourceStr = "N/A", symbol: Resource = $r("sys.symbol.ellipsis_message"),
  level: number = 0): void {
  void symbol
  const options: promptAction.ShowToastOptions = {
    message: text,
    duration: 1700,
    alignment: Alignment.Top,
    offset: {
      dx: 0,
      dy: 8
    },
    backgroundColor: level > 0 ? '#FDD9D9' : $r('sys.color.comp_background_primary'),
    textColor: level > 0 ? Color.Red : $r('sys.color.font_primary'),
    backgroundBlurStyle: BlurStyle.NONE
  }
  try {
    if (toastUiContext) {
      toastUiContext.getPromptAction().openToast(options).catch(() => {
      })
      return
    }
    promptAction.showToast(options)
  } catch (_) {
  }
}
