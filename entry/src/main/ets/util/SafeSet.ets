import Manager from "../Manager"
import { Config } from "./config/ETConfig"
import { elementCode, lwElementType, updateElement } from "./Conversion"

@ObservedV2
export class SafeSet<T> implements Iterable<T> {
  config: Config | undefined = undefined
  typeConstructor: () => T
  constructor(
    config: Config | undefined = undefined,
    constructorFunc: () => T = () => {return null as T}
  ) {
    this.config = config
    this.typeConstructor = constructorFunc
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
    }else if (elementCode(value as object).length > 0) {
      updateElement(value as lwElementType)
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
    }else if (elementCode(value as object).length > 0) {
      updateElement(value as lwElementType, false)
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