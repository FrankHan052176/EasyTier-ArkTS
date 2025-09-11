import { PlanetGraph } from './PlanetGraph'

@Entry
@ComponentV2
struct Index {
  build() {
    Row() {
      PlanetGraph()
    }
  }
}