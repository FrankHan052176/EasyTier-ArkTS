import easytier from "easytier-ohrs";
import { LogLocate } from "./util/Logger";
import { LightWeightMap } from "@kit.ArkTS";
import { COMBINED_CONFIG_FIELDS, IGNORED_CONFIG_FIELDS } from "./SchemaLayout";

@LogLocate("SchemaUtil")
export class SchemaUtil {
  schema: easytier.NetworkConfigSchema | undefined
  fieldMap = new LightWeightMap<string, easytier.NetworkConfigSchema>

  init() {
    this.fieldMap = new LightWeightMap<string, easytier.NetworkConfigSchema>()
    const parentField = new LightWeightMap<string, string>
    for (const key of Object.keys(COMBINED_CONFIG_FIELDS)) {
      for (const value of COMBINED_CONFIG_FIELDS[key]) {
        parentField.set(value, key)
      }
    }

    this.schema = easytier.getNetworkConfigSchema()
    this.collectFields(this.schema.children, parentField)
  }

  private collectFields(fields: easytier.NetworkConfigSchema[], parentField: LightWeightMap<string, string>) {
    for (const field of fields) {
      this.addField(field, parentField)
      if (field.children.length > 0) {
        this.collectFields(field.children, parentField)
      }
    }
  }

  private addField(field: easytier.NetworkConfigSchema, parentField: LightWeightMap<string, string>) {
    const fieldName = field.name
    if (IGNORED_CONFIG_FIELDS.has(fieldName)) {
      return
    }

    if (parentField.hasKey(fieldName)) {
      const parent = parentField.get(fieldName)
      if (this.fieldMap.hasKey(parent)) {
        this.fieldMap.get(parent).children.push(field)
      } else {
        this.fieldMap.set(parent, this.combineFields(parent, [field]))
      }
      return
    }

    this.fieldMap.set(fieldName, field)
  }

  private combineFields(fieldName: string, fields: easytier.NetworkConfigSchema[]): easytier.NetworkConfigSchema {
    return {
      nodeKind: 'combined',
      name: fieldName,
      fieldNumber: 0,
      typeName: undefined,
      semanticType: undefined,
      valueKind: 'combined',
      isList: false,
      required: false,
      defaultValueText: undefined,
      enumOptions: [],
      validations: [],
      children: fields,
      definitions: []
    }
  }
}
