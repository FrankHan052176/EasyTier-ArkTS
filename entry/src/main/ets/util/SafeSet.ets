import Manager from "../Manager"
import { Config } from "./config/ETConfig"

@ObservedV2
export class SafeSet<T> implements Iterable<T> {
  config: Config | undefined = undefined
  globalAddCallback: (value: T) => void
  globalDeleteCallback: (value: T) => void
  constructor(
    config: Config | undefined = undefined,
    addCallback: (value: T) => void = () => {},
    deleteCallback: (value: T) => void = () => {}
  ) {
    this.config = config
    this.globalAddCallback = addCallback
    this.globalDeleteCallback = deleteCallback
  }
  [Symbol.iterator](): IterableIterator<T> {
    return this.map.values()
  }
  @Trace map = new Map<String, T>
  has(value: T): boolean {
    return this.map.has(`${value}`)
  }
  add(value: T, update: boolean = true) {
    if (this.map.has(`${value}`)) return
    this.map.set(`${value}`, value)
    if (!update) return
    if (this.config && !this.config._disableUpdate) {
      Manager.updateConfig(this.config)
    }else {
      this.globalAddCallback(value)
    }
  }
   addSet(set: SafeSet<T>, update: boolean = true) {
    set.forEach((value) => {
      this.add(value, update)
    })
  }
  delete(value: T, update: boolean = true): boolean {
    let result = this.map.delete(`${value}`)
    if (!update) return result
    if (this.config && !this.config._disableUpdate) {
      Manager.updateConfig(this.config)
    }else {
      this.globalDeleteCallback(value)
    }
    return result
  }
  get size() {
    return this.map.size
  }
  values(): IterableIterator<T> {
    return this.map.values()
  }
  forEach(callback: (value: T) => void): void {
    this.map.forEach((value) => {
      callback(value)
    })
  }
  clear() {
    this.map.clear()
  }
}