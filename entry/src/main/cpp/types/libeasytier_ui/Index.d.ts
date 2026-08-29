import { NodeContent } from '@kit.ArkUI'

export interface NativeBoolTextModel {
  category: string
  text: string
  width: number
  height: number
  categoryColor: number
  textColor: number
}

export const createBoolText: (content: NodeContent, model: NativeBoolTextModel) => boolean
export const updateBoolText: (content: NodeContent, model: NativeBoolTextModel) => boolean
export const destroyBoolText: (content: NodeContent) => void
