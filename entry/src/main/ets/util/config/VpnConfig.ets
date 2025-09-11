export class Address {
  address: string;
  family: number;
  constructor(address: string, family: number) {
    this.address = address;
    this.family = family;
  }
}

export class AddressWithPrefix {
  address: Address;
  prefixLength: number;
  constructor(address: Address, prefixLength: number) {
    this.address = address;
    this.prefixLength = prefixLength;
  }
}

export interface DestinationItem {
  address: Address;
  prefixLength: number;
  port: number;
}

export interface GatewayItem {
  address: string;
  family: number;
  port: number;
}

export interface RouteConfig {
  interface: string;
  destination: DestinationItem;
  gateway: GatewayItem;
  hasGateway: boolean;
  isDefaultRoute: boolean;
}

export class VpnConfig {
  addresses: AddressWithPrefix[];
  mtu: number;
  dnsAddresses: string[];
  trustedApplications: string[];
  blockedApplications: string[];

  constructor(tunIp: string, mask: number, dns: string[] = ["223.5.5.5"]) {
    this.addresses = [
      new AddressWithPrefix(new Address(tunIp, 1), mask)
    ];
    this.mtu = 1500;
    this.dnsAddresses = dns;
    this.trustedApplications = [];
    this.blockedApplications = ["top.frankhan.easytier"];
  }
}