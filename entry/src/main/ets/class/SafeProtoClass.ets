import { PortForwardConfig } from '../protobuf/api_manage';
import { SecureModeConfig } from '../protobuf/common';

@Sendable
export class SafePortForwardConfig {
  bind_ip: string;
  bind_port: number;
  dst_ip: string;
  dst_port: number;
  proto: string;

  constructor(value: PortForwardConfig) {
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

@Sendable
export class SafeSecureModeConfig {
  enabled: boolean
  /** base64(X25519 private key), used by shared node to present a stable identity */
  local_private_key: string | undefined;
  /** base64(X25519 public key), required if local_private_key is set */
  local_public_key: string | undefined;

  constructor(value: SecureModeConfig) {
    this.enabled = value.enabled
    this.local_private_key = value.local_private_key
    this.local_public_key = value.local_public_key
  }

  toInterface(): SecureModeConfig {
    return {
      enabled: this.enabled,
      local_private_key: this.local_private_key,
      local_public_key: this.local_public_key
    }
  }
}