#!/usr/bin/env bash

set -euo pipefail
source "$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/common.sh"

[[ "$#" -eq 3 ]] ||
  die "Usage: $0 <signed-app> <sparkle-update-archive> <appcast.xml>"

APP_PATH="$1"
UPDATE_ARCHIVE="$2"
APPCAST_PATH="$3"

require_env EXPECTED_MARKETING_VERSION
require_env EXPECTED_BUILD_NUMBER
require_env EXPECTED_DOWNLOAD_URL
require_env SPARKLE_PUBLIC_ED_KEY
require_env SPARKLE_PRIVATE_ED_KEY_FILE
validate_version "$EXPECTED_MARKETING_VERSION"
validate_build_number "$EXPECTED_BUILD_NUMBER"

require_directory "$APP_PATH"
require_file "$UPDATE_ARCHIVE"
require_file "$APPCAST_PATH"
require_file "$SPARKLE_PRIVATE_ED_KEY_FILE"
require_command xmllint

INFO_PLIST="${APP_PATH}/Contents/Info.plist"
APP_RESOURCES="${APP_PATH}/Contents/Resources"
require_file "$INFO_PLIST"
require_file "${APP_RESOURCES}/LICENSE"
require_file "${APP_RESOURCES}/PRIVACY.md"
require_file "${APP_RESOURCES}/THIRD_PARTY_NOTICES.md"
require_file "${APP_RESOURCES}/Sparkle-LICENSE.txt"

read_plist_value() {
  /usr/libexec/PlistBuddy -c "Print :$1" "$INFO_PLIST"
}

ACTUAL_MARKETING_VERSION="$(read_plist_value CFBundleShortVersionString)"
ACTUAL_BUILD_NUMBER="$(read_plist_value CFBundleVersion)"
ACTUAL_PUBLIC_KEY="$(read_plist_value SUPublicEDKey)"

[[ "$ACTUAL_MARKETING_VERSION" == "$EXPECTED_MARKETING_VERSION" ]] ||
  die "Archived CFBundleShortVersionString is '${ACTUAL_MARKETING_VERSION}', expected '${EXPECTED_MARKETING_VERSION}'."
[[ "$ACTUAL_BUILD_NUMBER" == "$EXPECTED_BUILD_NUMBER" ]] ||
  die "Archived CFBundleVersion is '${ACTUAL_BUILD_NUMBER}', expected '${EXPECTED_BUILD_NUMBER}'."
[[ "$ACTUAL_PUBLIC_KEY" == "$SPARKLE_PUBLIC_ED_KEY" ]] ||
  die "The archived Sparkle public key does not match the configured release key."

DERIVED_PUBLIC_KEY="$(
  xcrun swift \
    "${ROOT_DIR}/Scripts/sparkle_public_key.swift" \
    "$SPARKLE_PRIVATE_ED_KEY_FILE"
)"
[[ "$DERIVED_PUBLIC_KEY" == "$SPARKLE_PUBLIC_ED_KEY" ]] ||
  die "The Sparkle private key does not derive the public key embedded in the application."

codesign --verify --deep --strict --verbose=2 "$APP_PATH"
xcrun stapler validate "$APP_PATH"
xmllint --noout "$APPCAST_PATH"

appcast_attribute() {
  xmllint \
    --xpath \
    "string((//*[local-name()='item']/*[local-name()='enclosure'])[1]/@*[local-name()='$1'])" \
    "$APPCAST_PATH"
}

appcast_element() {
  xmllint \
    --xpath \
    "string((//*[local-name()='item'])[1]/*[local-name()='$1'][1])" \
    "$APPCAST_PATH"
}

APPCAST_BUILD_NUMBER="$(appcast_element version)"
if [[ -z "$APPCAST_BUILD_NUMBER" ]]; then
  APPCAST_BUILD_NUMBER="$(appcast_attribute version)"
fi
APPCAST_MARKETING_VERSION="$(appcast_element shortVersionString)"
if [[ -z "$APPCAST_MARKETING_VERSION" ]]; then
  APPCAST_MARKETING_VERSION="$(appcast_attribute shortVersionString)"
fi
APPCAST_DOWNLOAD_URL="$(appcast_attribute url)"
APPCAST_LENGTH="$(appcast_attribute length)"
APPCAST_SIGNATURE="$(appcast_attribute edSignature)"
ARCHIVE_LENGTH="$(wc -c < "$UPDATE_ARCHIVE" | tr -d '[:space:]')"

[[ "$APPCAST_BUILD_NUMBER" == "$EXPECTED_BUILD_NUMBER" ]] ||
  die "Appcast build '${APPCAST_BUILD_NUMBER}' does not match '${EXPECTED_BUILD_NUMBER}'."
[[ "$APPCAST_MARKETING_VERSION" == "$EXPECTED_MARKETING_VERSION" ]] ||
  die "Appcast short version '${APPCAST_MARKETING_VERSION}' does not match '${EXPECTED_MARKETING_VERSION}'."
[[ "$APPCAST_DOWNLOAD_URL" == "$EXPECTED_DOWNLOAD_URL" ]] ||
  die "Appcast download URL '${APPCAST_DOWNLOAD_URL}' does not match the expected release URL."
[[ "$APPCAST_LENGTH" == "$ARCHIVE_LENGTH" ]] ||
  die "Appcast length '${APPCAST_LENGTH}' does not match archive length '${ARCHIVE_LENGTH}'."
[[ -n "$APPCAST_SIGNATURE" ]] ||
  die "The appcast enclosure is missing its Sparkle EdDSA signature."

SIGN_UPDATE="$(locate_sparkle_tool sign_update)"
"$SIGN_UPDATE" \
  --verify \
  --ed-key-file - \
  "$UPDATE_ARCHIVE" \
  "$APPCAST_SIGNATURE" < "$SPARKLE_PRIVATE_ED_KEY_FILE"

note "Release bundle metadata, legal resources, appcast, and EdDSA signature verified"
