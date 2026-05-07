import { AppManager } from '../../AppManager';
import { EventHelper } from '../../util/EventHelper';
import { Cidr, clearEditValue_Cidr, EditValue_Cidr, setEditValue_Cidr } from './Cidr';
import { clearEditValue_IP, EditValue_IP, IP, setEditValue_IP } from './IP';
import {
  clearEditValue_NetworkName,
  EditValue_NetworkName,
  NetworkName,
  setEditValue_NetworkName
} from './NetworkName';
import {
  clearEditValue_PortForward,
  EditValue_PortForward,
  PortForward,
  setEditValue_PortForward
} from './PortForward';
import { clearEditValue_Url, EditValue_Url, setEditValue_Url, Url } from './Url';
import { ConfigJson } from '../../config/schema/SchemaConfig';
import { syncTopLevelField } from '../../ConfigSyncUtil';
import { Logger } from '../../shared/logging/Logger';

export interface FieldValue {
  fromString(value: string): boolean

  toString(): string

  checkValid(): boolean

  bind(fieldName: string): FieldValue
}

let EditOriginalValue_Cidr: Cidr | undefined
let EditOriginalValue_Url: Url | undefined
let EditOriginalValue_IP: IP | undefined
let EditOriginalValue_NetworkName: NetworkName | undefined
let EditOriginalValue_PortForward: PortForward | undefined

export function setEditOriginalValue(type: string, value: FieldValue) {
  Logger.info(`setEditOriginalValue type=${type} value=${value.toString()}`, 'Basic')
  switch (type) {
    case "route":
    case "cidr":
      EditOriginalValue_Cidr = new Cidr().readFrom(value.toString())
      break
    case "mapped_listener":
    case "listener":
    case "peer":
      EditOriginalValue_Url = new Url()
      EditOriginalValue_Url.fromString(value.toString())
      break
    case "ip":
      EditOriginalValue_IP = new IP().readFrom(value.toString())
      break
    case "network_name":
      EditOriginalValue_NetworkName = new NetworkName()
      EditOriginalValue_NetworkName.fromString(value.toString())
      break
    case "port_forward":
      EditOriginalValue_PortForward = new PortForward()
      EditOriginalValue_PortForward.fromString(value.toString())
      break
  }
}

export function commitEditValue(config: ConfigJson, name: string, type: string): void {
  Logger.debug(`commitEditValue start field=${name} type=${type}`, 'Basic')
  switch (type) {
    case "route":
    case "cidr": {
      if (!EditOriginalValue_Cidr || !EditValue_Cidr) return
      const list = config[name] as string[]
      const index = list.indexOf(EditOriginalValue_Cidr.toString())
      if (index >= 0) {
        list[index] = EditValue_Cidr.toString()
        Logger.debug(`commitEditValue cidr field=${name} old=${EditOriginalValue_Cidr.toString()} new=${EditValue_Cidr.toString()}`, 'Basic')
      }
      break
    }
    case "mapped_listener":
    case "listener":
    case "peer": {
      if (!EditOriginalValue_Url || !EditValue_Url) return
      const list = config[name] as string[]
      const index = list.indexOf(EditOriginalValue_Url.toString())
      if (index >= 0) {
        list[index] = EditValue_Url.toString()
        Logger.debug(`commitEditValue url field=${name} old=${EditOriginalValue_Url.toString()} new=${EditValue_Url.toString()}`, 'Basic')
      }
      break
    }
    case "ip": {
      if (!EditOriginalValue_IP || !EditValue_IP) return
      const list = config[name] as string[]
      const index = list.indexOf(EditOriginalValue_IP.toString())
      if (index >= 0) {
        list[index] = EditValue_IP.toString()
        Logger.debug(`commitEditValue ip field=${name} old=${EditOriginalValue_IP.toString()} new=${EditValue_IP.toString()}`, 'Basic')
      }
      break
    }
    case "network_name": {
      if (!EditOriginalValue_NetworkName || !EditValue_NetworkName) return
      const list = config[name] as string[]
      const index = list.indexOf(EditOriginalValue_NetworkName.toString())
      if (index >= 0) {
        list[index] = EditValue_NetworkName.toString()
        Logger.debug(`commitEditValue network_name field=${name} old=${EditOriginalValue_NetworkName.toString()} new=${EditValue_NetworkName.toString()}`, 'Basic')
      }
      break
    }
    case "port_forward": {
      if (!EditOriginalValue_PortForward || !EditValue_PortForward) return
      const old: ESObject = EditOriginalValue_PortForward.toInterface()
      const list: ESObject[] = config[name] as ESObject[]
      const index = list.findIndex((element: ESObject) => element.bind_ip === old.bind_ip &&
        element.bind_port === old.bind_port && element.dst_ip === old.dst_ip &&
        element.dst_port === old.dst_port && element.proto === old.proto)
      if (index >= 0) {
        list[index] = EditValue_PortForward.toInterface()
        Logger.debug(`commitEditValue port_forward field=${name} replaced index=${index}`, 'Basic')
      }
      break
    }
  }
}

export function addFieldValue(type: string, name: string) {
  switch (type) {
    case "route":
    case "cidr": {
      setEditValue_Cidr(new Cidr())
      break;
    }
    case "mapped_listener":
    case "listener": {
      let value = new Url()
      value.domain = "0.0.0.0"
      setEditValue_Url(value)
      break;
    }
    case "peer": {
      setEditValue_Url(new Url())
      break;
    }
    case "ip": {
      setEditValue_IP(new IP())
      break;
    }
    case "network_name": {
      setEditValue_NetworkName(new NetworkName())
      break;
    }
    case "port_forward": {
      setEditValue_PortForward(new PortForward())
      break;
    }
  }
  EventHelper.emitterPublish("edit_open_sheet", {
    data: {
      type: "add_" + type + "|" + name
    }
  })
}

export function updateFieldValue(type: string, value: FieldValue) {
  switch (type) {
    case "route":
    case "cidr": {
      let cidr = value as Cidr
      if (EditValue_Cidr) {
        EditValue_Cidr.ip = cidr.ip
        EditValue_Cidr.mask = cidr.mask
      }
      break;
    }
    case "mapped_listener":
    case "listener":
    case "peer": {
      let url = value as Url
      if (EditValue_Url) {
        EditValue_Url.proto = url.proto
        EditValue_Url.domain = url.domain
        EditValue_Url.port = url.port
      }
      break;
    }
    case "ip": {
      let ip = value as IP
      if (EditValue_IP) {
        EditValue_IP.ip = ip.ip
      }
      break;
    }
    case "network_name": {
      let name = value as NetworkName
      if (EditValue_NetworkName) {
        EditValue_NetworkName.name = name.name
      }
      break;
    }
    case "port_forward": {
      let pf = value as PortForward
      if (EditValue_PortForward) {
        EditValue_PortForward.proto = pf.proto
        EditValue_PortForward.to = pf.to
        EditValue_PortForward.to_port = pf.to_port
        EditValue_PortForward.from = pf.from
        EditValue_PortForward.from_port = pf.from_port
      }
      break;
    }
  }
}

export function deleteFieldValue(config: ConfigJson, type: string, name: string, value: FieldValue) {
  if (type === "port_forward") {
    let i = -1
    let old: ESObject = (value as PortForward).toInterface()
    let arr: ESObject[] = config[name] as ESObject[]
    for (let index = 0; index < arr.length; index++) {
      const element: ESObject = arr[index];
      if (element.bind_ip === old.bind_ip &&
        element.bind_port === old.bind_port &&
        element.dst_ip === old.dst_ip &&
        element.dst_port === old.dst_port &&
        element.proto === old.proto
      ) {
        i = index
        break
      }
    }
    if (i >= 0) {
      arr.splice(i, 1)
    }
  } else {
    const pos = (config[name] as string[]).indexOf(value.toString())
    if (pos >= 0) {
      (config[name] as string[]).splice(pos, 1)
    }
  }
  syncTopLevelField(config.instance_id!, name, config)
}

export function clearEditValue(type: string) {
  switch (type) {
    case "route":
    case "cidr": {
      clearEditValue_Cidr()
      EditOriginalValue_Cidr = undefined
      break;
    }
    case "mapped_listener":
    case "listener":
    case "peer": {
      clearEditValue_Url()
      EditOriginalValue_Url = undefined
      break;
    }
    case "ip": {
      clearEditValue_IP()
      EditOriginalValue_IP = undefined
      break;
    }
    case "network_name": {
      clearEditValue_NetworkName()
      EditOriginalValue_NetworkName = undefined
      break;
    }
    case "port_forward": {
      clearEditValue_PortForward()
      EditOriginalValue_PortForward = undefined
      break;
    }
  }
}

export function confirmCheck(type: string): boolean {
  switch (type) {
    case "route":
    case "cidr": {
      return EditValue_Cidr?.checkValid() ?? false
    }
    case "mapped_listener":
    case "listener":
    case "peer": {
      return EditValue_Url?.checkValid() ?? false
    }
    case "ip": {
      return EditValue_IP?.checkValid() ?? false
    }
    case "network_name": {
      return EditValue_NetworkName?.checkValid() ?? false
    }
    case "port_forward": {
      return EditValue_PortForward?.checkValid() ?? false
    }
  }
  return false
}

export function addValue(name: string, type: string) {
  let config: ConfigJson = AppManager.easytier.getEditingConfig()!
  switch (type) {
    case "route":
    case "cidr": {
      animateToImmediately({
        curve: Curve.Ease,
        duration: 300
      }, () => {
        let raw = EditValue_Cidr!.toString()
        let list = config[name] as string[]
        if (list.indexOf(raw) < 0) {
          list.push(raw)
        }
        AppManager.data.getDataSource(type).add(EditValue_Cidr!)
        syncTopLevelField(config.instance_id!, name, config)
      })
      break;
    }
    case "mapped_listener":
    case "listener":
    case "peer": {
      animateToImmediately({
        curve: Curve.Ease,
        duration: 300
      }, () => {
        let raw = EditValue_Url!.toString()
        let list = config[name] as string[]
        if (list.indexOf(raw) < 0) {
          list.push(raw)
        }
        AppManager.data.getDataSource(type).add(EditValue_Url!)
        syncTopLevelField(config.instance_id!, name, config)
      })
      break;
    }
    case "ip": {
      animateToImmediately({
        curve: Curve.Ease,
        duration: 300
      }, () => {
        let raw = EditValue_IP!.toString()
        let list = config[name] as string[]
        if (list.indexOf(raw) < 0) {
          list.push(raw)
        }
        AppManager.data.getDataSource(type).add(EditValue_IP!)
        syncTopLevelField(config.instance_id!, name, config)
      })
      break;
    }
    case "network_name": {
      animateToImmediately({
        curve: Curve.Ease,
        duration: 300
      }, () => {
        let raw = EditValue_NetworkName!.toString()
        let list = config[name] as string[]
        if (list.indexOf(raw) < 0) {
          list.push(raw)
        }
        AppManager.data.getDataSource(type).add(EditValue_NetworkName!)
        syncTopLevelField(config.instance_id!, name, config)
      })
      break;
    }
    case "port_forward": {
      let raw: ESObject = EditValue_PortForward!.toInterface()
      let list: ESObject[] = config[name] as ESObject[]
      if (list.indexOf(raw) < 0) {
        list.push(raw)
      }
      AppManager.data.getDataSource(type).add(EditValue_PortForward!)
      syncTopLevelField(config.instance_id!, name, config)
      break;
    }
  }
}
