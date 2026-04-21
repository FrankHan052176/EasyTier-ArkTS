import { Logger, LogLocate } from "./util/Logger";
import { vpnExtension } from "@kit.NetworkKit";
import { socket } from "@kit.NetworkKit";
import { common } from "@kit.AbilityKit";
import { AppManager } from "./AppManager";

export const vpn_socket: string = "vpn"

@LogLocate("SocketUtil")
export class SocketUtil {
  client: socket.LocalSocket | undefined;
  init() {
    vpnExtension.startVpnExtensionAbility({
      deviceId: '',
      bundleName: 'top.frankhan.easytier',
      abilityName: 'EasyTierAbility',
      parameters: {
        socket: vpn_socket
      }
    })
    setTimeout(() => {
      this.client = socket.constructLocalSocketInstance();
      this.client.on('connect', () => {
        Logger.debug(`Client connect`)
      });
      let context: common.UIAbilityContext = AppManager.content.context! as common.UIAbilityContext;
      let sandboxPath: string = context.filesDir + '/../../../files/' + vpn_socket;
      Logger.info(`path: ${sandboxPath}`);
      let localAddress : socket.LocalAddress = {
        address: sandboxPath
      }
      let connectOpt: socket.LocalConnectOptions = {
        address: localAddress,
        timeout: 6000
      }
      this.client.on("message", (value: socket.LocalSocketMessageInfo) => {
        let time = Date.now()
        const uintArray = new Uint8Array(value.message);
        let messageView = '';
        for (let i = 0; i < uintArray.length; i++) {
          messageView += String.fromCharCode(uintArray[i]);
        }
        Logger.debug("receive message: "+messageView+","+time)
      })
      this.client.on("close", () => {
        Logger.debug("closed connection")
      })
      this.client.connect(connectOpt).then(() => {
        Logger.info(`Client connect success`);
      }).catch((err: Object) => {
        Logger.error('fail to connect: ' + JSON.stringify(err));
      });
    }, 200)
  }
}