export class NetworkSegment {
  networkAddress: string = '';
  prefix: number = 0;

  constructor(segmentStr: string) {
    this.parseSegment(segmentStr);
  }

  contains(target: string): boolean {
    try {
      const targetNetwork = target.includes('/')
        ? new NetworkSegment(target)
        : this.ipToNetwork(target, 32);

      const networkNum = this.ipToNumber(this.networkAddress);
      const targetNetworkNum = this.ipToNumber(targetNetwork.networkAddress);

      const mask = this.prefixToMask(this.prefix);
      const maskNum = this.ipToNumber(mask.join('.'));

      return (networkNum & maskNum) === (targetNetworkNum & maskNum) &&
        this.prefix <= targetNetwork.prefix;
    } catch {
      return false;
    }
  }

  toString(): string {
    return `${this.networkAddress}/${this.prefix}`;
  }

  private parseSegment(segmentStr: string): void {
    const split = segmentStr.split('/');
    const ip = split[0];
    const prefixStr = split[1] ?? "24";

    if (!ip || !prefixStr) {
      throw new Error('Invalid network segment format. Expected: IP/Prefix');
    }

    this.prefix = parseInt(prefixStr);
    if (this.prefix < 0 || this.prefix > 32) {
      throw new Error('Prefix must be between 0 and 32');
    }

    // 计算网络地址
    this.networkAddress = this.calculateNetworkAddress(ip.trim(), this.prefix);
  }

  private calculateNetworkAddress(ip: string, prefix: number): string {
    const ipBytes = ip.split('.').map(octet => parseInt(octet));
    const mask = this.prefixToMask(prefix);

    const networkBytes = ipBytes.map((byte, i) => byte & mask[i]);
    return networkBytes.join('.');
  }

  private prefixToMask(prefix: number): number[] {
    const mask = [0, 0, 0, 0];
    for (let i = 0; i < 4; i++) {
      if (prefix >= 8) {
        mask[i] = 255;
        prefix -= 8;
      } else {
        mask[i] = 256 - (1 << (8 - prefix));
        break;
      }
    }
    return mask;
  }

  private ipToNumber(ip: string): number {
    const bytes = ip.split('.').map(octet => parseInt(octet));
    return (bytes[0] << 24) | (bytes[1] << 16) | (bytes[2] << 8) | bytes[3];
  }

  private ipToNetwork(ip: string, prefix: number): NetworkSegment {
    const segment = new NetworkSegment('0.0.0.0/0');
    segment.networkAddress = this.calculateNetworkAddress(ip, prefix);
    segment.prefix = prefix;
    return segment;
  }
}