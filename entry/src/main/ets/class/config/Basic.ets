import { AppManager } from "../../AppManager";
import { ContentUtil } from "../../ContentUtil";
import { NetworkConfig } from "../../protobuf/api_manage";
import { EventHelper } from "../../util/EventHelper";
import { Cidr, clearEditValue_Cidr, EditValue_Cidr, setEditValue_Cidr } from "./Cidr";
import { clearEditValue_IP, EditValue_IP, IP, setEditValue_IP } from "./IP";
import {
  clearEditValue_NetworkName,
  EditValue_NetworkName, NetworkName, setEditValue_NetworkName } from "./NetworkName";
import { clearEditValue_Url, EditValue_Url, setEditValue_Url, Url } from "./Url";

export interface FieldValue {
  fromString(value: string): boolean
  toString(): string
  checkValid(): boolean
  bind(fieldName: string): FieldValue
}

export function addFieldValue(type: string, name: string) {
  switch (type) {
    case "route":
    case "cidr": {
      setEditValue_Cidr(new Cidr())
      break;
    }
    case "mappedListener":
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
    case "string": {
      setEditValue_NetworkName(new NetworkName())
      break;
    }
    case "port_forward": {
      // TODO 端口转发
      break;
    }
  }
  EventHelper.emitterPublish("edit_open_sheet",{
    data: {
      type: "add_"+type+"_"+name
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
    case "mappedListener":
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
    case "string": {
      setEditValue_NetworkName(new NetworkName())
      let name = value as NetworkName
      if (EditValue_NetworkName) {
        EditValue_NetworkName.name = name.name
      }
      break;
    }
    case "port_forward": {
      // TODO 端口转发
      break;
    }
  }
}

export function deleteFieldValue(config: NetworkConfig, type: string, name: string, value: FieldValue) {
  const pos = (config[ContentUtil.safeFieldName(name)] as string[]).indexOf(value.toString())
  if (pos >= 0) {
    (config[ContentUtil.safeFieldName(name)] as string[]).splice(pos, 1)
  }
  animateToImmediately({
    curve: Curve.Ease,
    duration: 300
  }, () => {
    AppManager.data.getDataSource(type).del(value)
  })
}

export function clearEditValue(type: string) {
  switch (type) {
    case "route":
    case "cidr": {
      clearEditValue_Cidr()
      break;
    }
    case "mappedListener":
    case "listener":
    case "peer": {
      clearEditValue_Url()
      break;
    }
    case "ip": {
      clearEditValue_IP()
      break;
    }
    case "string": {
      clearEditValue_NetworkName()
      break;
    }
    case "port_forward": {
      // TODO 端口转发 清空临时变量
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
    case "mappedListener":
    case "listener":
    case "peer": {
      return EditValue_Url?.checkValid() ?? false
    }
    case "ip": {
      return EditValue_IP?.checkValid() ?? false
    }
    case "string": {
      return EditValue_NetworkName?.checkValid() ?? false
    }
    case "port_forward": {
      // TODO 端口转发 检查文本合法
      return false
    }
  }
  return false
}

export function addValue(name:string, type: string) {
  let config = AppManager.data.configUUIDMap.get(AppManager.data.editingInstance!)!
  switch (type) {
    case "route":
    case "cidr": {
      animateToImmediately({
        curve: Curve.Ease,
        duration: 300
      }, () => {
        let raw = EditValue_Cidr!.toString()
        if ((config[name] as string[]).indexOf(raw) < 0) {
          config[name].push(raw)
        }
        AppManager.data.getDataSource(type).add(EditValue_Cidr!)
      })
      break;
    }
    case "mappedListener":
    case "listener":
    case "peer": {
      animateToImmediately({
        curve: Curve.Ease,
        duration: 300
      }, () => {
        config[name].push(EditValue_Url!.toString())
        AppManager.data.getDataSource(type).add(EditValue_Url!)
      })
      break;
    }
    case "ip": {
      animateToImmediately({
        curve: Curve.Ease,
        duration: 300
      }, () => {
        config[name].push(EditValue_IP!.toString())
        AppManager.data.getDataSource(type).add(EditValue_IP!)
      })
      break;
    }
    case "string": {
      animateToImmediately({
        curve: Curve.Ease,
        duration: 300
      }, () => {
        config[name].push(EditValue_NetworkName!.toString())
        AppManager.data.getDataSource(type).add(EditValue_NetworkName!)
      })
      break;
    }
    case "port_forward": {
      // TODO 端口转发 新增配置
      break;
    }
  }
}