import Manager from "../Manager"
import { Config } from "./config/ETConfig"
import { LightWeightMap } from "@kit.ArkTS"

@ObservedV2
export class SafeLightWeightSet<T> implements IDataSource {
  config: Config | undefined = undefined
  globalAddCallback: (value: T) => void
  globalDeleteCallback: (value: T) => void
  @Trace map = new LightWeightMap<String, T>
  private listeners: DataChangeListener[] = [];
  constructor(
    config: Config | undefined = undefined,
    addCallback: (value: T) => void = () => {},
    deleteCallback: (value: T) => void = () => {}
  ) {
    this.config = config
    this.globalAddCallback = addCallback
    this.globalDeleteCallback = deleteCallback
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

  has(value: T): boolean {
    return this.map.hasKey(`${value}`)
  }
  add(value: T, update: boolean = true) {
    if (this.map.hasKey(`${value}`)) return
    this.map.set(`${value}`, value)
    this.notifyDataAdd(this.map.getIndexOfKey(`${value}`))
    if (!update) return
    if (this.config && !this.config._disableUpdate) {
      Manager.updateConfig(this.config)
    }else {
      this.globalAddCallback(value)
    }
  }
  addSet(set: SafeLightWeightSet<T>, update: boolean = true) {
    set.forEach((value) => {
      this.add(value, update)
    })
  }
  delete(value: T, update: boolean = true): boolean {
    if (!this.map.hasKey(`${value}`)) return false
    try {
      this.notifyDataDelete(this.map.getIndexOfKey(`${value}`))
      this.map.remove(`${value}`)
      if (!update) return true
      if (this.config && !this.config._disableUpdate) {
        Manager.updateConfig(this.config)
      }else {
        this.globalDeleteCallback(value)
      }
      return true
    } catch (error) {
      return false
    }
  }
  get size() {
    return this.map.length
  }
  forEach(callback: (value: T) => void): void {
    this.map.forEach((value) => {
      callback(value!!)
    })
  }
  clear() {
    this.map.clear()
  }
}