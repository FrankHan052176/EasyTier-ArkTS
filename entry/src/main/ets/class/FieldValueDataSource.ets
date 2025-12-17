import { AppManager } from '../AppManager';
import { Logger, LogLocate } from '../util/Logger';
import { FieldValue } from './config/Basic';

@LogLocate("FieldValueDataSource")
@ObservedV2
export class FieldValueDataSource implements IDataSource {
  private listeners: DataChangeListener[] = [];
  @Trace values: FieldValue[] = [];
  type: string

  constructor(type: string, values: FieldValue[] = []) {
    Logger.debug("datasource with type:" + type, this)
    this.type = type
    this.values = values
  }

  totalCount(): number {
    return this.values.length
  }

  getData(index: number): FieldValue {
    return this.values[index]
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    if (this.listeners.indexOf(listener) < 0) {
      this.listeners.push(listener);
    }
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    const pos = this.listeners.indexOf(listener);
    if (pos >= 0) {
      this.listeners.splice(pos, 1);
    }
  }

  notifyDataReload(): void {
    this.listeners.forEach(listener => {
      listener.onDataReloaded();
    });
  }

  notifyDataAdd(index: number): void {
    this.listeners.forEach(listener => {
      listener.onDataAdd(index);
    });
  }

  notifyDataChange(index: number): void {
    this.listeners.forEach(listener => {
      listener.onDataChange(index);
    });
  }

  notifyDataDelete(index: number): void {
    this.listeners.forEach(listener => {
      listener.onDataDelete(index);
    });
  }

  notifyDataMove(from: number, to: number): void {
    this.listeners.forEach(listener => {
      listener.onDataMove(from, to);
    });
  }

  notifyDatasetChange(operations: DataOperation[]): void {
    this.listeners.forEach(listener => {
      listener.onDatasetChange(operations);
    });
  }

  has(value: FieldValue): boolean {
    for (const item of this.values) {
      if (item.toString() === value.toString()) {
        return true
      }
    }
    return false
  }

  add(value: FieldValue): boolean {
    if (!this.has(value)) {
      this.notifyDataAdd(this.values.push(value))
      AppManager.preference.globalConfigs?.putSync(this.type, this.values.map((value) => value.toString()))
      AppManager.preference.globalConfigs?.flushSync()
      return true
    } else {
      return false
    }
  }

  del(value: FieldValue): boolean {
    if (this.has(value)) {
      let index = this.values.indexOf(value)
      this.values.splice(index, 1)
      AppManager.preference.globalConfigs?.putSync(this.type, this.values.map((value) => value.toString()))
      AppManager.preference.globalConfigs?.flushSync()
      this.notifyDataDelete(index)
      return true
    } else {
      return false
    }
  }

  update() {
    AppManager.preference.globalConfigs?.putSync(this.type, this.values.map((value) => value.toString()))
    AppManager.preference.globalConfigs?.flushSync()
  }
}