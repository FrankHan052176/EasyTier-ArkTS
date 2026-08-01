const JSON_SECRET_PATTERN = /(\"(?:network_secret|secret|password|token|private_key|privateKey)\"\s*:\s*)\"(?:[^\"\\]|\\.)*\"/gi
const TOML_SECRET_PATTERN = /((?:network_secret|secret|password|token|private_key|private_key_file)\s*=\s*)\"[^\"]*\"/gi

export function redactSensitiveLogText(value: string): string {
  return value
    .replace(JSON_SECRET_PATTERN, '$1"[REDACTED]"')
    .replace(TOML_SECRET_PATTERN, '$1"[REDACTED]"')
}
