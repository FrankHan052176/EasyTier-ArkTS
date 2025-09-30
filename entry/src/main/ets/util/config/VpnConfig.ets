export class NetAddress {
  address: string;
  family: number;
  port: number;
  constructor(address: string, family: number, port: number = 0) {
    this.address = address;
    this.family = family;
    this.port = port
  }
}

export class AddressWithPrefix {
  address: NetAddress;
  prefixLength: number;
  constructor(address: NetAddress, prefixLength: number) {
    this.address = address;
    this.prefixLength = prefixLength;
  }
}

export interface LinkAddress {
  address: NetAddress;
  prefixLength: number;
}

export interface GatewayItem {
  address: string;
  family: number;
  port: number;
}

export class RouteConfig {
  interface: string = "vpn-tun";
  destination: LinkAddress;
  gateway: 	NetAddress;
  hasGateway: boolean;
  isDefaultRoute: boolean;
  constructor(destination: LinkAddress, gateway: NetAddress | undefined, isDefaultRoute: boolean) {
    this.destination = destination;
    this.gateway = gateway?gateway:new NetAddress("", 1);
    this.hasGateway = gateway === undefined
    this.isDefaultRoute = isDefaultRoute
  }
}

export class VpnConfig {
  addresses: Array<AddressWithPrefix>;
  mtu: number;
  dnsAddresses: Array<string>;
  trustedApplications: Array<string>;
  blockedApplications: Array<string>;
  // routes: Array<RouteConfig>;

  constructor(tunIp: string, mask: number, dns: Array<string> = ["223.5.5.5"]) {
    this.addresses = [
      new AddressWithPrefix(new NetAddress(tunIp, 1), mask)
    ];

    this.mtu = 1500;
    this.dnsAddresses = dns;
    this.trustedApplications = [];
    this.blockedApplications = ["top.frankhan.easytier"];
    // this.routes = [
    //   new RouteConfig({
    //     address: new NetAddress("10.53.176.0", 1),
    //     prefixLength: 24
    //   },new NetAddress("10.53.176.1", 1),true),
    //   new RouteConfig({
    //     address: new NetAddress("10.52.176.0", 1),
    //     prefixLength: 24
    //   },new NetAddress("10.53.176.1", 1),true),
    //   new RouteConfig({
    //     address: new NetAddress("100.100.100.101", 1),
    //     prefixLength: 32
    //   },new NetAddress("10.53.176.1", 1),false)
    // ]
  }
}