import { PeerInfo } from '../InstanceInfo';

@ObservedV2
export class LogDataSource implements IDataSource {
  private listeners: DataChangeListener[] = [];
  @Trace private logs: string[] = [];

  totalCount(): number {
    return this.logs.length
  }

  getData(index: number): string {
    return this.logs[index]
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

  add(log: string) {
    this.notifyDataAdd(this.logs.push(log)-1)
  }

  addFrom(log: string[]) {
    let len = this.logs.push(...log)
    this.notifyDatasetChange([
      {
        type: DataOperationType.ADD,
        index: len-log.length,
        count: log.length
      }
    ])
  }

  del(index: number) {
    this.logs.splice(index,1)
    this.notifyDataDelete(index)
  }

  join2String() {
    return this.logs.join("\n")
  }
}