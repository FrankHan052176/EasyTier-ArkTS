@ComponentV2
export struct DiscoverBall {
  @Param @Require yellow: boolean
  @Param comp_size: number = 42
  @Local wave_scale: number = 1
  @Local wave_opacity: number = 1
  @Local center_opacity: number = 1

  @Computed
  get center_size() {
    return this.comp_size / 3
  }

  aboutToAppear(): void {
    animateToImmediately({
      duration: 2000,
      curve: Curve.Ease,
      iterations: -1
    }, () => {
      this.wave_scale = 3
      this.wave_opacity = 0
    })
    animateToImmediately({
      duration: 1000,
      curve: Curve.EaseInOut,
      playMode: PlayMode.Alternate,
      iterations: -1
    }, () => {
      this.center_opacity = 0.5
    })
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      Stack()
        .width(this.center_size)
        .height(this.center_size)
        .backgroundColor(this.yellow ? 'rgba(255,200,50,1)' : "#4ade80")
        .borderRadius(360)
        .scale({
          x: this.wave_scale,
          y: this.wave_scale
        })
        .opacity(this.wave_opacity)
      Circle().width(this.center_size).height(this.center_size)
        .foregroundColor(this.yellow ? 'rgba(255,200,50,1)' : "#4ade80")
        .opacity(this.center_opacity)
    }.width(this.comp_size).height(this.comp_size)
  }
}