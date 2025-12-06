export enum Protocol {
  TCP = "tcp",
  TCP6 = "tcp6",
  UDP = "udp",
  UDP6 = "udp6",
  QUIC = "quic",
  QUIC6 = "quic6",
  WS = "ws",
  WS6 = "ws6",
  WSS = "wss",
  WSS6 = "wss6",
  WG = "wg",
  WG6 = "wg6",
  TXT = "txt",
  UNKNOWN = ""
}
export const protocols = [Protocol.TCP, Protocol.UDP, Protocol.QUIC, Protocol.WS, Protocol.WSS, Protocol.WG, Protocol.TXT]
export const protocolsWithoutTXT = [Protocol.TCP, Protocol.UDP, Protocol.QUIC, Protocol.WS, Protocol.WSS, Protocol.WG]
export const protocolsOnlyTcpAndUdp = [Protocol.TCP, Protocol.UDP]
export function convertToProtocol(input: string): Protocol {
  switch (input) {
    case "udp": return Protocol.UDP;
    case "udp6": return Protocol.UDP6;
    case "quic": return Protocol.QUIC;
    case "quic6": return Protocol.QUIC6;
    case "ws": return Protocol.WS;
    case "ws6": return Protocol.WS6;
    case "wss": return Protocol.WSS;
    case "wss6": return Protocol.WSS6;
    case "wg": return Protocol.WG;
    case "wg6": return Protocol.WG6;
    case "txt": return Protocol.TXT;
    default : return Protocol.TCP;
  }
}
export function protocolColor(protocol:Protocol): ResourceColor {
  switch (protocol) {
    case Protocol.UDP: return "#ffd94838";
    case Protocol.QUIC: return "#ff800080";
    case Protocol.WS: return "#ff64bb5c";
    case Protocol.WSS: return "#ff5ba854";
    case Protocol.WG: return "#ffed6f21";
    case Protocol.TXT: return $r("sys.color.font_on_primary");
    default : return "#ff0a59f7";
  }
}
export function protocolBGColor(protocol:Protocol): ResourceColor {
  switch (protocol) {
    case Protocol.UDP: return "#33d94838";
    case Protocol.QUIC: return "#33800080";
    case Protocol.WS: return "#3364bb5c";
    case Protocol.WSS: return "#335ba854";
    case Protocol.WG: return "#33ed6f21";
    case Protocol.TXT: return $r("sys.color.font_primary");
    default : return "#330a59f7";
  }
}