import { SymbolGlyphModifier } from '@kit.ArkUI'
import { HdsNavigationMenuItemOptions, IconStyleMode } from '@kit.UIDesignKit'

function symbolWithSize(symbol: Resource, size: number): SymbolGlyphModifier {
  let result = new SymbolGlyphModifier(symbol)
  result.fontSize(size)
  result.fontColor([$r("sys.color.font_primary")])
  return result
}

export function HdsMenuButton(value: ResourceStr, symbol: Resource,
  callback: () => void, id: string | undefined = undefined): HdsNavigationMenuItemOptions {
  return {
    content: {
      icon: symbolWithSize(symbol, 24),
      label: value,
      componentId: id,
      action: () => {
        callback()
      },
      type: IconStyleMode.LARGE
    }
  }
}
