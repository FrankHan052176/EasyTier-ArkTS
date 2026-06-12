import { ConfigField, configFieldRegistry } from '../fields/ConfigFieldRegistry'
import { EditRenderNode, EditRenderPlan, EditSectionRenderPlan } from './EditRenderNode'

const SUPPORTED_LIST_TYPES: ReadonlySet<string> = new Set([
  'cidr',
  'route',
  'peer',
  'mapped_listener',
  'listener',
  'ip',
  'network_name',
  'port_forward'
])

function isListType(type: string): boolean {
  return type.endsWith('[]')
}

function getListItemType(field: ConfigField): string | undefined {
  if (typeof field.type === 'string' && isListType(field.type)) {
    const itemType = field.type.slice(0, field.type.length - 2)
    return SUPPORTED_LIST_TYPES.has(itemType) ? itemType : undefined
  }
  if (field.semanticType && isListType(field.semanticType)) {
    const itemType = field.semanticType.slice(0, field.semanticType.length - 2)
    return SUPPORTED_LIST_TYPES.has(itemType) ? itemType : undefined
  }
  return undefined
}

function topLevelField(path: string[], fallback: string): string {
  return path.length > 0 ? path[0] : fallback
}

function unique(values: string[]): string[] {
  const seen = new Set<string>()
  const result: string[] = []
  values.forEach((value) => {
    if (value.length > 0 && !seen.has(value)) {
      seen.add(value)
      result.push(value)
    }
  })
  return result
}

function isCidrComposite(children: EditRenderNode[]): boolean {
  if (children.length !== 2) {
    return false
  }
  return children[0].field.type === 'cidr_ip' && children[1].field.type === 'cidr_mask'
}

function resolvePrimitiveKind(field: ConfigField): EditRenderNode['kind'] {
  if (typeof field.type !== 'string') {
    return 'group'
  }
  if (getListItemType(field)) {
    return 'list'
  }
  if (field.isList) {
    return 'unsupported'
  }
  if (field.enumOptions.length > 0 || field.type === 'enum' || field.valueKind === 'enum') {
    return 'enum'
  }
  if (field.type === 'boolean' || field.valueKind === 'boolean') {
    return 'boolean'
  }
  if (field.type === 'string' || field.type === 'cidr_ip' || field.type === 'ip' || field.valueKind === 'string') {
    return 'string'
  }
  if (field.type === 'number' || field.type === 'cidr_mask' || field.valueKind === 'number') {
    return 'number'
  }
  if (field.type === 'port') {
    return 'port'
  }
  return 'unsupported'
}

export function resolveEditRenderNode(field: ConfigField, layer: number = 0): EditRenderNode {
  const children = Array.isArray(field.type)
    ? field.type.map((child) => resolveEditRenderNode(child, layer + 1))
    : []
  let kind: EditRenderNode['kind'] = Array.isArray(field.type) ? 'group' : resolvePrimitiveKind(field)
  let listType: string | undefined
  let enableNode: EditRenderNode | undefined

  if (Array.isArray(field.type)) {
    const semanticListType = getListItemType(field)
    if (semanticListType) {
      kind = 'list'
      listType = semanticListType
    } else if (field.isList) {
      kind = 'unsupported'
    } else if (isCidrComposite(children)) {
      kind = 'cidr'
    } else if (children.length > 0 && children[0].kind === 'boolean' && field.name !== 'flags_switch') {
      enableNode = children[0]
    }
  } else {
    listType = getListItemType(field)
  }

  return {
    name: field.name,
    path: field.path,
    renderKey: `${field.path.join('.')}:${kind}`,
    topLevelField: topLevelField(field.path, field.name),
    kind,
    field,
    children,
    listType,
    enumOptions: (field.enumOptions ?? []).map((option) => {
      return {
        label: option.label.length > 0 ? option.label : option.value,
        value: option.value
      }
    }),
    layer,
    enableNode
  }
}

function section(key: string, title: string, fields: ConfigField[]): EditSectionRenderPlan {
  const nodes = fields.map((field) => resolveEditRenderNode(field))
  const topFields: string[] = []
  nodes.forEach((node) => {
    collectTopLevelFields(node).forEach((field) => topFields.push(field))
  })
  return {
    key,
    title,
    nodes,
    topLevelFields: unique(topFields)
  }
}

export function collectTopLevelFields(node: EditRenderNode): string[] {
  if ((node.kind === 'group' || node.kind === 'cidr') && node.children.length > 0) {
    const values: string[] = []
    node.children.forEach((child) => {
      collectTopLevelFields(child).forEach((field) => values.push(field))
    })
    return unique(values)
  }
  return unique([node.topLevelField])
}

export function buildEditRenderPlan(): EditRenderPlan {
  if (cachedEditRenderPlan) {
    return cachedEditRenderPlan
  }
  configFieldRegistry.init()
  cachedEditRenderPlan = {
    sections: [
      section('basic', '基础', configFieldRegistry.basicFields),
      section('flags', '开关', [configFieldRegistry.flagField]),
      section('advanced', '高级', configFieldRegistry.advancedFields),
      section('other', '其他', configFieldRegistry.otherFields)
    ]
  }
  return cachedEditRenderPlan
}

let cachedEditRenderPlan: EditRenderPlan | undefined = undefined

export function warmEditRenderPlan(): void {
  buildEditRenderPlan()
}

export function emptyEditRenderPlan(): EditRenderPlan {
  return {
    sections: []
  }
}

export function findEditSection(plan: EditRenderPlan, key: string): EditSectionRenderPlan | undefined {
  return plan.sections.find((item) => item.key === key)
}
