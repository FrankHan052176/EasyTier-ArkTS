import Manager from "../Manager"
import { Config } from "./config/ETConfig"
import { LightWeightMap } from "@kit.ArkTS"
import { SafeSet } from "./SafeSet"
import { elementCode, lwElementType, updateElement } from "./Conversion"

@ObservedV2
export class SafeLightWeightSet<T> implements IDataSource {
  config: Config | undefined = undefined
  @Trace map = new LightWeightMap<String, T>
  @Trace setSize = 0
  private listeners: DataChangeListener[] = [];
  typeConstructor: () => T
  @Trace fresh: boolean = false
  @Trace disableUpdate: boolean = false
  constructor(
    config: Config | undefined = undefined,
    constructorFunc: () => T = ()=>{return null as T}
  ) {
    this.config = config
    this.typeConstructor = constructorFunc
  }

  doDisableUpdate(): SafeLightWeightSet<T> {
    this.disableUpdate = true
    return this
  }

  totalCount(): number {
    return this.map.length
  }

  getData(index: number): T {
    return this.map.getValueAt(index)
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    if (this.listeners.indexOf(listener) < 0) {
      console.info('add listener');
      this.listeners.push(listener);
    }
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    const pos = this.listeners.indexOf(listener);
    if (pos >= 0) {
      console.info('remove listener');
      this.listeners.splice(pos, 1);
    }
  }

  notifyDataAdd(index: number): void {
    this.listeners.forEach(listener => {
      listener.onDataAdd(index);
    })
  }

  notifyDataDelete(index: number): void {
    this.listeners.forEach(listener => {
      listener.onDataDelete(index);
    })
  }
  refresh() {
    this.fresh = !this.fresh
  }
  has(value: T): boolean {
    return this.map.hasKey(`${value}`)
  }
  add(value: T, update: boolean = true) {
    if (this.map.hasKey(`${value}`)) return
    this.map.set(`${value}`, value)
    this.setSize++
    this.refresh()
    this.notifyDataAdd(this.map.getIndexOfKey(`${value}`))
    if (!update || this.disableUpdate) return
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
  addLightWeightSet(set: SafeLightWeightSet<T>, update: boolean = true) {
    set.forEach((value) => {
      this.add(value, update)
    })
  }
  syncModify(set: SafeLightWeightSet<T>, update: boolean = true) {
    let addItems: T[] = []
    let delItems: T[] = []
    this.forEach((value) => {
      if (!set.has(value)) {
        delItems.push(value)
      }
    })
    set.forEach((value) => {
      if (!this.has(value)) {
        addItems.push(value)
      }
    })
    delItems.forEach((value) => {
      this.delete(value, update)
    })
    addItems.forEach((value) => {
      this.add(value, update)
    })
  }
  delete(value: T, update: boolean = true): boolean {
    if (!this.map.hasKey(`${value}`)) return false
    try {
      this.notifyDataDelete(this.map.getIndexOfKey(`${value}`))
      this.map.remove(`${value}`)
      this.setSize--
      this.refresh()
      if (!update || this.disableUpdate) return true
      if (this.config && !this.config._disableUpdate) {
        Manager.updateConfig(this.config)
      }else if (elementCode(value as object).length > 0) {
        updateElement(value as lwElementType, false)
      }
      return true
    } catch (error) {
      return false
    }
  }
  get size() {
    return this.setSize
  }
  forEach(callback: (value: T) => void): void {
    this.map.forEach((value) => {
      callback(value!!)
    })
  }
  clear() {
    this.forEach((value) => {
      if (!this.config) {
        if (elementCode(value as object).length > 0) {
          updateElement(value as lwElementType, false)
        }
      }
    })
    this.map.clear()
    this.refresh()
    if (this.config) {
      Manager.updateConfig(this.config)
    }
  }
  toIterator(): IterableIterator<T> {
    return this.map.values()
  }
}