import { FieldValue } from "./config/Basic";

@ObservedV2
export class FieldValueDataSource implements IDataSource {
  private listeners: DataChangeListener[] = [];
  @Trace values: FieldValue[] = [];
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
      return true
    }else {
      return false
    }
  }

  del(value: FieldValue): boolean {
    if (this.has(value)) {
      let index = this.values.indexOf(value)
      this.values.splice(index, 1)
      this.notifyDataDelete(index)
      return true
    }else {
      return false
    }
  }
}