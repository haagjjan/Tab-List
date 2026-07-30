#!/usr/bin/env bash

set -euo pipefail
source "$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/common.sh"

require_full_xcode
require_env CODE_SIGN_IDENTITY

[[ "$#" -eq 3 ]] || die "Usage: $0 <notarized-app> <version> <output-directory>"
APP_PATH="$1"
VERSION="$2"
OUTPUT_DIR="$3"

require_directory "$APP_PATH"
validate_version "$VERSION"
require_command ditto
require_command hdiutil
require_file "${ROOT_DIR}/LICENSE"
require_file "${ROOT_DIR}/PRIVACY.md"
require_file "${ROOT_DIR}/THIRD_PARTY_NOTICES.md"
require_file "${ROOT_DIR}/Resources/Legal/Sparkle-LICENSE.txt"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"
xcrun stapler validate "$APP_PATH"

APP_RESOURCES="${APP_PATH}/Contents/Resources"
require_file "${APP_RESOURCES}/LICENSE"
require_file "${APP_RESOURCES}/PRIVACY.md"
require_file "${APP_RESOURCES}/THIRD_PARTY_NOTICES.md"
require_file "${APP_RESOURCES}/Sparkle-LICENSE.txt"

mkdir -p "$OUTPUT_DIR"
TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/tablist-package.XXXXXX")"
trap 'rm -rf -- "$TEMP_DIR"' EXIT

PRODUCT_BASENAME="TabList-${VERSION}"
ZIP_PATH="${OUTPUT_DIR}/${PRODUCT_BASENAME}.zip"
DMG_PATH="${OUTPUT_DIR}/${PRODUCT_BASENAME}.dmg"
DMG_ROOT="${TEMP_DIR}/dmg"
DOCUMENTATION_ROOT="${DMG_ROOT}/Documentation"
mkdir -p "$DOCUMENTATION_ROOT"

note "Creating Sparkle update archive"
ditto -c -k --keepParent --sequesterRsrc "$APP_PATH" "$ZIP_PATH"

note "Creating user-facing disk image"
ditto "$APP_PATH" "${DMG_ROOT}/TabList.app"
ditto "${ROOT_DIR}/LICENSE" "${DOCUMENTATION_ROOT}/TabList-LICENSE.txt"
ditto "${ROOT_DIR}/PRIVACY.md" "${DOCUMENTATION_ROOT}/PRIVACY.md"
ditto "${ROOT_DIR}/THIRD_PARTY_NOTICES.md" "${DOCUMENTATION_ROOT}/THIRD_PARTY_NOTICES.md"
ditto "${ROOT_DIR}/Resources/Legal/Sparkle-LICENSE.txt" "${DOCUMENTATION_ROOT}/Sparkle-LICENSE.txt"
ln -s /Applications "${DMG_ROOT}/Applications"
hdiutil create \
  -volname "Tab-List ${VERSION}" \
  -srcfolder "$DMG_ROOT" \
  -ov \
  -format UDZO \
  "$DMG_PATH"
codesign \
  --force \
  --timestamp \
  --sign "$CODE_SIGN_IDENTITY" \
  "$DMG_PATH"
codesign --verify --strict --verbose=2 "$DMG_PATH"

note "Created ${ZIP_PATH}"
note "Created ${DMG_PATH}"
