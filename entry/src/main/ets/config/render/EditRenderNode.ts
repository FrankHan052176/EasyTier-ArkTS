import { ConfigField } from '../fields/ConfigFieldRegistry'

export type EditRenderKind =
  'group' |
  'boolean' |
  'string' |
  'number' |
  'port' |
  'cidr' |
  'list' |
  'enum' |
  'unsupported'

export interface EditRenderOption {
  label: string
  value: string
}

export interface EditRenderNode {
  name: string
  path: string[]
  renderKey: string
  topLevelField: string
  kind: EditRenderKind
  field: ConfigField
  children: EditRenderNode[]
  listType?: string
  enumOptions: EditRenderOption[]
  layer: number
  enableNode?: EditRenderNode
}

export interface EditSectionRenderPlan {
  key: string
  title: string
  nodes: EditRenderNode[]
  topLevelFields: string[]
}

export interface EditRenderPlan {
  sections: EditSectionRenderPlan[]
}
