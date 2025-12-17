import { SymbolGlyphModifier } from '@kit.ArkUI'
import { HdsNavigationMenuItemOptions, IconStyleMode } from '@kit.UIDesignKit'
import { symbolWithSize } from './hmrouter/HomePage'

export function MenuButton(value: string | Resource, symbol: Resource, callback: () => void): NavigationMenuItem {
  return {
    'value': value, 'symbolIcon': new SymbolGlyphModifier(symbol), 'action': () => {
      callback()
    }
  }
}

export function HdsMenuButton(value: ResourceStr, symbol: Resource,
  callback: () => void): HdsNavigationMenuItemOptions {
  return {
    content: {
      icon: symbolWithSize(symbol, 24),
      label: value,
      action: () => {
        callback()
      },
      type: IconStyleMode.LARGE
    }
  }
}