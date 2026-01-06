import { ContentUtil } from './ContentUtil';
import { NetworkConfig } from './protobuf/api_manage';
import { NetworkConfigFieldIdMap, NetworkConfigIdFieldMap } from './protobuf/proto-type-map';

function cleanEmpty(value: any) {
  if (value === undefined) {
    return undefined;
  }
  if (Array.isArray(value) && value.length === 0) {
    return undefined;
  }
  return value;
}

export function mappedJson(raw: NetworkConfig): string {
  let data = {};
  for (const [key, value] of Object.entries(raw)) {
    const mappedKey = NetworkConfigFieldIdMap[key] || key;
    let val = cleanEmpty(value)
    if (val) {
      data[mappedKey] = val;
    }
  }
  return JSON.stringify(data)
}

export function unmappedJson(raw: string): NetworkConfig {
  let data = ContentUtil.getDefaultConfig("")
  for (const [key, value] of Object.entries(JSON.parse(raw))) {
    const mappedKey = NetworkConfigIdFieldMap[key] || key;
    data[mappedKey] = value;
  }
  return data
}