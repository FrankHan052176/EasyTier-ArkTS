import { url } from '@kit.ArkTS'
import { AppManager } from '../../AppManager'
import { Logger, LogLocate } from '../../shared/logging/Logger'
import { unwrapUrl } from '../../util/ShareUtil'

export enum ConfigTextImportKind {
  Empty = 'empty',
  ShareLink = 'share_link',
  Toml = 'toml',
  Unsupported = 'unsupported'
}

export interface ConfigTextImportResult {
  success: boolean
  kind: ConfigTextImportKind
  message: string
  sourceText?: string
}

function isHttpUrl(text: string): boolean {
  const lower = text.toLowerCase()
  return lower.startsWith('http://') || lower.startsWith('https://')
}

@LogLocate('ConfigTextImportService')
export class ConfigTextImportService {
  static async importText(text: string): Promise<ConfigTextImportResult> {
    if (text.length === 0) {
      return {
        success: false,
        kind: ConfigTextImportKind.Empty,
        message: '剪切板中没有内容'
      }
    }

    if (isHttpUrl(text)) {
      try {
        const urlObject = url.URL.parseURL(text)
        if (await unwrapUrl(urlObject)) {
          return {
            success: true,
            kind: ConfigTextImportKind.ShareLink,
            message: '导入成功',
            sourceText: text
          }
        }
      } catch (error) {
        Logger.debug(`import url failed: ${JSON.stringify(error)}`, 'ConfigTextImportService')
      }
      return {
        success: false,
        kind: ConfigTextImportKind.Unsupported,
        message: '导入失败，请导入标准 EasyTier 分享链接',
        sourceText: text
      }
    }

    if (AppManager.data.importToml(text)) {
      return {
        success: true,
        kind: ConfigTextImportKind.Toml,
        message: '导入成功',
        sourceText: text
      }
    }

    Logger.debug(`unsupported import text: ${text.substring(0, 256)}`, 'ConfigTextImportService')
    return {
      success: false,
      kind: ConfigTextImportKind.Unsupported,
      message: '导入失败，请导入标准 Toml 配置或 EasyTier 分享链接',
      sourceText: text
    }
  }
}
