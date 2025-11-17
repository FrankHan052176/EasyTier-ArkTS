import { VpnExtensionAbility } from "@kit.NetworkKit";
import { Logger } from "../util/Logger";

export default class EasyTierAbility extends VpnExtensionAbility {
  onCreate(): void {
    Logger.debug("VpnExtAbi create")
  }
}