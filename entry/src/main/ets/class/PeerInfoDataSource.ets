import { PeerInfo } from './InstanceInfo';

@ObservedV2
export class PeerInfoDataSource implements IDataSource {
  private listeners: DataChangeListener[] = [];
  @Trace private values: Map<number, PeerInfo> = new Map();
  @Trace private idArray: number[] = [];

  totalCount(): number {
    return this.idArray.length
  }

  getData(index: number): PeerInfo {
    return this.values.get(this.idArray[index])!
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

  set(peer: PeerInfo) {
    if (this.values.has(peer.peerId)) {
      let index = this.idArray.indexOf(peer.peerId)
      let info = this.values.get(peer.peerId)
      if (info) {
        info.update(peer)
        this.notifyDataChange(index)
      }
    } else {
      let index = this.idArray.push(peer.peerId) - 1
      this.values.set(peer.peerId, peer)
      this.notifyDataAdd(index)
    }
  }

  del(peerId: number) {
    if (this.values.has(peerId)) {
      let index = this.idArray.indexOf(peerId)
      this.idArray.splice(index, 1)
      this.notifyDataDelete(index)
    }
  }
}