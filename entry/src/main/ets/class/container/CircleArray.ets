import { Logger } from "../../util/Logger"

export class CircleArray<T> {
  arr: Array<T>
  private index: number = 0
  private size: number
  sum: number = 0
  private full: boolean = false
  constructor(size: number) {
    this.size = size
    this.arr = new Array<T>(size)
  }
  push(value: T) {
    let old = this.arr[this.index]
    if (this.full && typeof old === "number") {
      this.sum -= old
    }
    this.arr[this.index] = value
    if (!this.full && this.index === this.size - 1) {
      this.full = true
    }
    this.index = (this.index + 1) % this.size
    if (typeof value === "number") {
      this.sum += value
    }
  }
}