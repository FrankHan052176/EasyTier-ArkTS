import { getFieldI18nKey } from '../../config/fields/ConfigFieldUi'

export function getFieldI18Name(field: string): ResourceStr {
  return $r("app.string." + getFieldI18nKey(field))
}
