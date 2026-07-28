#!/usr/bin/env bash

set -euo pipefail

: "${CODEARTS_PRIVATE_OHPM_READ:?CODEARTS_PRIVATE_OHPM_READ is required}"
: "${CORE_HAR_PACKAGE:?CORE_HAR_PACKAGE is required}"
: "${CORE_HAR_VERSION:?CORE_HAR_VERSION is required}"
: "${CORE_HAR_DESTINATION:?CORE_HAR_DESTINATION is required}"

CORE_HAR_MODULE_NAME="${CORE_HAR_MODULE_NAME:-easytier-ohrs}"

if [[ ! "$CORE_HAR_PACKAGE" =~ ^[a-z][a-z0-9._-]{0,127}$ ]]; then
  echo "Invalid Core HAR package name." >&2
  exit 1
fi
if [[ ! "$CORE_HAR_VERSION" =~ ^[0-9A-Za-z][0-9A-Za-z.+-]{0,126}$ ]]; then
  echo "Invalid Core HAR package version." >&2
  exit 1
fi
if [[ ! "$CORE_HAR_MODULE_NAME" =~ ^[a-z][a-z0-9._-]{0,127}$ ]]; then
  echo "Invalid stable HAR module name." >&2
  exit 1
fi

temp_parent="${RUNNER_TEMP:-${TMPDIR:-/tmp}}"
fetch_root=$(mktemp -d "$temp_parent/easytier-core-har.XXXXXX")
cleanup() {
  rm -rf "$fetch_root"
}
trap cleanup EXIT

mkdir -p "$HOME/.ohpm"
printf '%s' "$CODEARTS_PRIVATE_OHPM_READ" > "$HOME/.ohpm/.ohpmrc"
chmod 600 "$HOME/.ohpm/.ohpmrc"
ohpm config set strict_ssl false

printf '%s\n' \
  '{' \
  '  "modelVersion": "5.0.0",' \
  '  "dependencies": {},' \
  '  "devDependencies": {}' \
  '}' > "$fetch_root/oh-package.json5"

(
  cd "$fetch_root"
  ohpm install \
    "${CORE_HAR_PACKAGE}@${CORE_HAR_VERSION}" \
    --no-save \
    --retry_times 5 \
    --retry_interval 3000
)

installed_link="$fetch_root/oh_modules/$CORE_HAR_PACKAGE"
if [[ ! -d "$installed_link" ]]; then
  echo "OHPM did not install the requested Core HAR." >&2
  exit 1
fi
installed_package=$(cd "$installed_link" && pwd -P)

jq -e \
  --arg name "$CORE_HAR_PACKAGE" \
  --arg version "$CORE_HAR_VERSION" \
  '.name == $name and .version == $version' \
  "$installed_package/oh-package.json5" >/dev/null
if [[ -n "${CORE_SHA:-}" ]]; then
  grep -F -- "- Core commit: $CORE_SHA" \
    "$installed_package/CHANGELOG.md" >/dev/null
fi

repack_root="$fetch_root/repack"
mkdir -p "$repack_root/package"
cp -aL "$installed_package/." "$repack_root/package/"
jq --arg name "$CORE_HAR_MODULE_NAME" \
  '.name = $name' \
  "$repack_root/package/oh-package.json5" \
  > "$repack_root/package/oh-package.tmp.json5"
mv "$repack_root/package/oh-package.tmp.json5" \
  "$repack_root/package/oh-package.json5"

test -s "$repack_root/package/libs/arm64-v8a/libeasytier_ohrs.so"
mkdir -p "$(dirname "$CORE_HAR_DESTINATION")"
tar -czf "$CORE_HAR_DESTINATION" -C "$repack_root" package

jq -e \
  --arg name "$CORE_HAR_MODULE_NAME" \
  --arg version "$CORE_HAR_VERSION" \
  '.name == $name and .version == $version' \
  <(tar -xOzf "$CORE_HAR_DESTINATION" package/oh-package.json5) >/dev/null

if command -v sha256sum >/dev/null 2>&1; then
  prepared_sha256=$(sha256sum "$CORE_HAR_DESTINATION" | awk '{print $1}')
else
  prepared_sha256=$(shasum -a 256 "$CORE_HAR_DESTINATION" | awk '{print $1}')
fi
printf 'Prepared %s@%s as %s (%s)\n' \
  "$CORE_HAR_PACKAGE" \
  "$CORE_HAR_VERSION" \
  "$CORE_HAR_MODULE_NAME" \
  "$prepared_sha256"
