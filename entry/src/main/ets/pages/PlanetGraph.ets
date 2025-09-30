import { convertDeviceNumberToSymbol } from '../util/Conversion'
import Manager from '../Manager'
import Logger from '../util/Logger'
import { isGetDistributePerm } from '../util/Permission'
import EventHelper from '../util/EventHelper'
import { CircleShape } from '@kit.ArkUI'
import { Config, peer } from '../util/config/ETConfig'
import { uniformTypeDescriptor } from '@kit.ArkData'
import { SatelliteGraph } from './SatelliteGraph'

@Observed
export class Pos {
  x: number = 0
  y: number = 0
}

@Component
export struct PlanetGraph {
  config: Config = new Config()
  @State deviceType: number = 0
  @Provide Diameter: number = 72
  @Provide lightOffsetX: number = this.Diameter/2*(1+Math.cos(Math.PI/4))
  @Provide lightOffsetY: number = this.Diameter/2*(1-Math.sin(Math.PI/4))
  @Provide planetX: number = 0
  @Provide planetY: number = 0
  @State satellitePositions: Pos[] = []
  @State waveOpacity: number = 0.8
  @State waveScale: ScaleOptions = { x: 1, y: 1 }
  @State lightOffsetScale: number = 6

  aboutToAppear(): void {
    EventHelper.emitterListener("update_distribute", () => {
      Logger.debug("[PlanetGraph] update_distribute:"+Manager.distributePerm)
      this.deviceType = isGetDistributePerm()?Manager.deviceManager.getLocalDeviceType():0
    })
    this.deviceType = isGetDistributePerm()?Manager.deviceManager.getLocalDeviceType():0
    this.config.peer.forEach((_value:peer) => {
      this.satellitePositions.push({x:100,y:100})
    })
  }

  build() {
    Stack() {
      Circle({ width: this.Diameter, height: this.Diameter })
        .fill($r("app.color.homo_blue"))
        .opacity(this.waveOpacity)
        .scale(this.waveScale)
        .zIndex(1)
        .animation({ duration: 1300, iterations: -1, curve: Curve.EaseInOut })
      Circle({ width: this.Diameter, height: this.Diameter })
        .fill(Color.Transparent)
        .zIndex(2)
        .radialGradient({
          center: [this.lightOffsetX, this.lightOffsetY],
          radius: this.Diameter,
          colors: [[0xffffff, 0], [0x99ccff, 0.3], [$r("app.color.homo_blue"), 0.65], [0x0066ff, 0.8], [0x0055cc, 1]]
        })
        .clipShape(new CircleShape({ width: this.Diameter, height: this.Diameter }))
        .allowDrop([uniformTypeDescriptor.UniformDataType.PLAIN_TEXT])
        .onAreaChange((_:Area, newArea:Area) => {
          this.planetX = (newArea.position.x as number)+this.Diameter/2
          this.planetY = (newArea.position.y as number)+this.Diameter/2
          this.waveOpacity = 0.0
          this.waveScale = { x: 6, y: 6 }
        })
      SymbolGlyph(convertDeviceNumberToSymbol(this.deviceType))
        .fontSize(30)
        .fontColor([$r("app.color.symbol_color")])
        .opacity(0.85)
        .zIndex(30)
    }
    .height('100%')
    .width('100%')
    .alignContent(Alignment.Center)
  }
}