@ComponentV2
export struct DiscoverBall {
  @Param @Require yellow: boolean
  @Param comp_size: number = 42

  @Computed
  get center_size() {
    return this.comp_size / 3
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      Stack()
        .width(this.center_size)
        .height(this.center_size)
        .backgroundColor(this.yellow ? 'rgba(255,200,50,1)' : "#4ade80")
        .borderRadius(360)
        .scale({
          x: 2,
          y: 2
        })
        .opacity(0.2)
      Circle().width(this.center_size).height(this.center_size)
        .foregroundColor(this.yellow ? 'rgba(255,200,50,1)' : "#4ade80")
        .opacity(0.9)
    }.width(this.comp_size).height(this.comp_size)
  }
}
