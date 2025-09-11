@ObservedV2
export class TrafficArray {
  @Trace data: number[] = new Array(30).fill(0);

  push(item: number): void {
    this.data.push(item);
    if (this.data.length > 30) {
      this.data.shift();
    }
  }

  getAll(): number[] {
    return this.data;
  }

  clear(): void {
    this.data = [];
  }

  isEmpty(): boolean {
    return this.data.length === 0;
  }

  isFull(): boolean {
    return this.data.length === 30;
  }
}