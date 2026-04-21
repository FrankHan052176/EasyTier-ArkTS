import { VpnExtensionAbility } from '@kit.NetworkKit';
import { Logger } from '../util/Logger';
import Want from '@ohos.app.ability.Want';
import { socket } from '@kit.NetworkKit';
import { fileIo } from '@kit.CoreFileKit';

export default class EasyTierAbility extends VpnExtensionAbility {
  server: socket.LocalSocketServer | undefined

  onCreate(want: Want): void {
    Logger.debug("VpnExtAbi create", "EasyTierAbility")
    if (want.parameters == undefined) return;
    this.server = socket.constructLocalSocketServerInstance();
    let context = this.context.getApplicationContext()
    let sandboxPath: string = context.filesDir + '/' + want.parameters["socket"];
    fileIo.unlinkSync(sandboxPath)
    let listenAddr: socket.LocalAddress = {
      address: sandboxPath
    }
    this.server.listen(listenAddr).then(() => {
      Logger.debug(`Server listening on ${sandboxPath}`)
    }).catch((err: object) => {
      Logger.error(`Server listen error: ${JSON.stringify(err)}`)
    });
    this.server.on('connect', (connection: socket.LocalSocketConnection) => {
      connection.send({
        data: 'test'
      }).then(() => {
        Logger.debug(`send`+Date.now())
      }).catch((err: object) => {
        Logger.error('fail to send data: ' + JSON.stringify(err));
      });
      connection.on('error', (err: Object) => {
        Logger.error(`Connection error: ${JSON.stringify(err)}`);
      });
      connection.on('message', (value: socket.LocalSocketMessageInfo) => {
        let message = value.message
      });
    });
  }
}