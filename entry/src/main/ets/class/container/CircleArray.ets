@ObservedV2
export class CircleArray<T> {
  @Trace arr: Array<T>
  @Trace sum: number = 0
  @Trace private index: number = 0
  @Trace private size: number
  @Trace private full: boolean = false
  @Trace private count: number = 0

  constructor(size: number) {
    this.size = size
    this.arr = new Array<T>(size)
  }

  push(value: T): void {
    let old = this.arr[this.index]
    if (this.full && typeof old === "number") {
      this.sum -= old
    }
    this.arr[this.index] = value
    if (!this.full && this.index === this.size - 1) {
      this.full = true
    }
    if (this.count < this.size) {
      this.count++
    }
    this.index = (this.index + 1) % this.size
    if (typeof value === "number") {
      this.sum += value
    }
  }

  get average(): number {
    return this.count > 0 ? this.sum / this.count : 0
  }

  clear(): void {
    this.arr = new Array<T>(this.size)
    this.sum = 0
    this.index = 0
    this.full = false
    this.count = 0
  }
}
