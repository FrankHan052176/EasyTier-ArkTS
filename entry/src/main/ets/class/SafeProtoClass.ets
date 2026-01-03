import { PortForwardConfig } from "../protobuf/api_manage";

@Sendable
export class SafePortForwardConfig {
  bind_ip: string;
  bind_port: number;
  dst_ip: string;
  dst_port: number;
  proto: string;
  constructor(value:PortForwardConfig) {
    this.bind_ip = value.bind_ip
    this.bind_port = value.bind_port
    this.dst_ip = value.dst_ip
    this.dst_port = value.dst_port
    this.proto = value.proto
  }
  toInterface(): PortForwardConfig {
    return {
      bind_ip: this.bind_ip,
      bind_port: this.bind_port,
      dst_ip: this.dst_ip,
      dst_port: this.dst_port,
      proto: this.proto
    }
  }
}