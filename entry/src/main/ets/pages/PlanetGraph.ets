import { convertDeviceNumberToSymbol, convertDeviceTypeToSymbol } from '../util/Conversion'
import Manager from '../Manager'
import Logger from '../util/Logger'

@ComponentV2
export struct PlanetGraph {
  aboutToAppear(): void {
    Logger.info("device"+Manager.deviceManager.getLocalDeviceType())
  }

  build() {
    Stack() {
      SymbolGlyph(convertDeviceNumberToSymbol(Manager.deviceManager.getLocalDeviceType()))
    }
    .width('100%')
    .height('100%')
    .alignContent(Alignment.Center)
  }
}