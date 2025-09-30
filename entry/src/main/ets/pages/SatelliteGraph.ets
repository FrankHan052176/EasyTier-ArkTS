import { CircleShape } from "@kit.ArkUI";
import { Config, peer } from "../util/config/ETConfig";

@Component
export struct SatelliteGraph {
  @Consume Diameter: number
  @Consume planetX: number
  @Consume planetY: number
  @Link config: Config
  @Prop peer: peer
  @State satelliteScale: number = 0.7
  @State x: number = 0
  @State y: number = 0
  @State positionX: number = this.x;
  @State positionY: number = this.y;
  @State lightOffsetX: number = this.Diameter*this.satelliteScale/2*(1+Math.cos(Math.PI/4))
  @State lightOffsetY: number = this.Diameter*this.satelliteScale/2*(1-Math.sin(Math.PI/4))
  @State use: boolean = false
  dragWork: boolean = true
  isDragging: boolean = false
  roundAngle: number = 1
  roundCos: number = Math.cos(-this.roundAngle * (Math.PI / 180))
  roundSin: number = Math.sin(-this.roundAngle * (Math.PI / 180))

  aboutToAppear(): void {
    setInterval(() => {
      if (!this.isDragging) {
        animateToImmediately({
          duration: 50, curve: Curve.Linear
        },() => {
          this.x = this.x * this.roundCos - this.y * this.roundSin
          this.y = this.x * this.roundSin + this.y * this.roundCos
          this.positionX = this.x;
          this.positionY = this.y;
        })
      }
    }, 50)
  }

  build() {
    Circle({ width: this.Diameter*this.satelliteScale, height: this.Diameter*this.satelliteScale })
      .fill(Color.Transparent)
      .translate({ x: this.x, y: this.y, z: 0 })
      .zIndex(20)
      .radialGradient({
        center: [this.lightOffsetX, this.lightOffsetY],
        radius: this.Diameter*this.satelliteScale,
        colors: this.use?
          [[0xffffff, 0], [0x99ccff, 0.3], [$r("app.color.homo_blue"), 0.65], [0x0066ff, 0.8], [0x0055cc, 1]]:
          [[0xffffff, 0], [0x999999, 0.3], [$r("app.color.second_color"), 0.65], [0x555555, 0.8], [0x333333, 1]]
      })
      .clipShape(new CircleShape({ width: this.Diameter*this.satelliteScale, height: this.Diameter*this.satelliteScale }))
      .gesture(
        PanGesture()
          .onActionStart(() => {
            this.isDragging = true
          })
          .onActionUpdate((event: GestureEvent | undefined) => {
            if (event && this.dragWork) {
              let eX = this.positionX + event.offsetX
              let eY = this.positionY + event.offsetY
              if (eX * eX + eY * eY > this.Diameter * this.Diameter * (this.satelliteScale/2 + 0.5) * (this.satelliteScale/2 + 0.5)) {
                this.x = eX;
                this.y = eY;
                if (this.use) {
                  animateToImmediately({
                    duration: 500, curve: Curve.EaseInOut
                  },() => {
                    this.use = false
                  })
                }
              }else {
                let value = Math.sqrt(this.x*this.x+this.y*this.y)
                this.x = this.x/value*(this.Diameter*(0.5+this.satelliteScale/2)+5)
                this.y = this.y/value*(this.Diameter*(0.5+this.satelliteScale/2)+5)
                this.dragWork = false
                animateToImmediately({
                  duration: 500, curve: Curve.EaseInOut
                },() => {
                  this.use = true
                })
              }
            }
          })
          .onActionEnd(() => {
            this.positionX = this.x;
            this.positionY = this.y;
            this.dragWork = true;
            this.isDragging = false
          })
      )
  }
}