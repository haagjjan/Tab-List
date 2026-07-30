#!/usr/bin/env bash

set -euo pipefail
source "$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/common.sh"

require_full_xcode
require_env DEVELOPMENT_TEAM
require_env CODE_SIGN_IDENTITY
require_env MARKETING_VERSION
require_env BUILD_NUMBER
require_env SPARKLE_PUBLIC_ED_KEY
require_command codesign
require_command ditto
require_command plutil

validate_version "$MARKETING_VERSION"
validate_build_number "$BUILD_NUMBER"
generate_project

ARCHIVE_PATH="${ARCHIVE_PATH:-${ROOT_DIR}/build/TabList.xcarchive}"
EXPORT_PATH="${EXPORT_PATH:-${ROOT_DIR}/build/Export}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-${ROOT_DIR}/build/DerivedData}"
mkdir -p "$(dirname -- "$ARCHIVE_PATH")"

remove_existing_output() {
  local path="$1"
  local description="$2"
  [[ -n "$path" && "$path" != "/" && "$path" != "." ]] ||
    die "Refusing to remove unsafe ${description} path '${path}'."
  [[ "$path" != "$ROOT_DIR" ]] ||
    die "Refusing to remove the repository root as ${description}."
  if [[ -e "$path" || -L "$path" ]]; then
    note "Removing previous ${description} at ${path}"
    rm -rf -- "$path"
  fi
}

[[ "$ARCHIVE_PATH" == *.xcarchive ]] ||
  die "ARCHIVE_PATH must end in .xcarchive."
case "$(basename -- "$EXPORT_PATH")" in
  *Export* | *export*) ;;
  *) die "EXPORT_PATH basename must identify an export directory." ;;
esac
remove_existing_output "$ARCHIVE_PATH" "archive"
remove_existing_output "$EXPORT_PATH" "export directory"

note "Archiving Tab-List ${MARKETING_VERSION} (${BUILD_NUMBER})"
xcodebuild \
  archive \
  -project "${ROOT_DIR}/TabList.xcodeproj" \
  -scheme TabList \
  -configuration Release \
  -destination "generic/platform=macOS" \
  -archivePath "$ARCHIVE_PATH" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  ARCHS=arm64 \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGN_STYLE=Manual \
  DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" \
  CODE_SIGN_IDENTITY="$CODE_SIGN_IDENTITY" \
  MARKETING_VERSION="$MARKETING_VERSION" \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  SPARKLE_PUBLIC_ED_KEY="$SPARKLE_PUBLIC_ED_KEY" \
  OTHER_CODE_SIGN_FLAGS="--timestamp"

APP_PATH="${ARCHIVE_PATH}/Products/Applications/TabList.app"
require_directory "$APP_PATH"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"

TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/tablist-export.XXXXXX")"
trap 'rm -rf -- "$TEMP_DIR"' EXIT
EXPORT_OPTIONS_PLIST="${TEMP_DIR}/ExportOptions.plist"
plutil -create xml1 "$EXPORT_OPTIONS_PLIST"
plutil -insert method -string developer-id "$EXPORT_OPTIONS_PLIST"
plutil -insert destination -string export "$EXPORT_OPTIONS_PLIST"
plutil -insert signingStyle -string manual "$EXPORT_OPTIONS_PLIST"
plutil -insert teamID -string "$DEVELOPMENT_TEAM" "$EXPORT_OPTIONS_PLIST"
plutil -insert signingCertificate -string "$CODE_SIGN_IDENTITY" \
  "$EXPORT_OPTIONS_PLIST"
plutil -insert stripSwiftSymbols -bool true "$EXPORT_OPTIONS_PLIST"
plutil -insert manageAppVersionAndBuildNumber -bool false \
  "$EXPORT_OPTIONS_PLIST"

if [[ -n "${EXPORT_OPTIONS_EVIDENCE_PATH:-}" ]]; then
  mkdir -p "$(dirname -- "$EXPORT_OPTIONS_EVIDENCE_PATH")"
  ditto "$EXPORT_OPTIONS_PLIST" "$EXPORT_OPTIONS_EVIDENCE_PATH"
fi

note "Exporting the archived application for Developer ID distribution"
xcodebuild \
  -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_PATH" \
  -exportOptionsPlist "$EXPORT_OPTIONS_PLIST"

EXPORTED_APP_PATH="${EXPORT_PATH}/TabList.app"
require_directory "$EXPORTED_APP_PATH"
codesign --verify --deep --strict --verbose=2 "$EXPORTED_APP_PATH"

note "Archive created at ${ARCHIVE_PATH}"
note "Developer ID application exported to ${EXPORTED_APP_PATH}"
