import { PeerInfo } from '../InstanceInfo';

@ObservedV2
export class LogDataSource implements IDataSource {
  private listeners: DataChangeListener[] = [];
  @Trace private logs: string[] = [];
  private readonly maxLogs: number = 500;

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

  private trimOverflow(): number {
    const overflow = this.logs.length - this.maxLogs
    if (overflow > 0) {
      this.logs.splice(0, overflow)
    }
    return overflow
  }

  add(log: string) {
    const index = this.logs.push(log) - 1
    if (this.trimOverflow() > 0) {
      this.notifyDataReload()
    } else {
      this.notifyDataAdd(index)
    }
  }

  addFrom(log: string[]) {
    if (log.length === 0) {
      return
    }
    const len = this.logs.push(...log)
    if (this.trimOverflow() > 0) {
      this.notifyDataReload()
      return
    }
    this.notifyDatasetChange([{
      type: DataOperationType.ADD,
      index: len - log.length,
      count: log.length
    }])
  }

  del(index: number) {
    this.logs.splice(index,1)
    this.notifyDataDelete(index)
  }

  join2String() {
    return this.logs.join("\n")
  }
}
