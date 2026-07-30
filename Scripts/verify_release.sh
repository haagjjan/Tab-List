#!/usr/bin/env bash

set -euo pipefail
source "$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/common.sh"

[[ "$#" -ge 4 && "$#" -le 5 ]] ||
  die "Usage: $0 <signed-app> <sparkle-zip> <signed-dmg> <appcast.xml> [evidence-directory]"

APP_PATH="$1"
UPDATE_ARCHIVE="$2"
DMG_PATH="$3"
APPCAST_PATH="$4"

require_env EXPECTED_MARKETING_VERSION
require_env EXPECTED_BUILD_NUMBER
require_env EXPECTED_DOWNLOAD_URL
require_env EXPECTED_BUNDLE_IDENTIFIER
require_env EXPECTED_DEVELOPMENT_TEAM
require_env EXPECTED_CODE_SIGN_IDENTITY
require_env EXPECTED_FEED_URL
require_env EXPECTED_SOURCE_COMMIT
require_env EXPECTED_TAG
require_env EXPECTED_PRERELEASE
require_env SPARKLE_PUBLIC_ED_KEY
require_env SPARKLE_PRIVATE_ED_KEY_FILE

validate_version "$EXPECTED_MARKETING_VERSION"
validate_build_number "$EXPECTED_BUILD_NUMBER"
[[ "$EXPECTED_SOURCE_COMMIT" =~ ^[0-9a-fA-F]{40}$ ]] ||
  die "EXPECTED_SOURCE_COMMIT must be a full 40-character Git commit."
[[ "$EXPECTED_TAG" == "v${EXPECTED_MARKETING_VERSION}" ]] ||
  die "EXPECTED_TAG must be v${EXPECTED_MARKETING_VERSION}."
[[ "$EXPECTED_PRERELEASE" == "true" ||
   "$EXPECTED_PRERELEASE" == "false" ]] ||
  die "EXPECTED_PRERELEASE must be true or false."

require_directory "$APP_PATH"
require_file "$UPDATE_ARCHIVE"
require_file "$DMG_PATH"
require_file "$APPCAST_PATH"
require_file "$SPARKLE_PRIVATE_ED_KEY_FILE"
require_command codesign
require_command ditto
require_command file
require_command hdiutil
require_command jq
require_command lipo
require_command plutil
require_command shasum
require_command spctl
require_command stat
require_command xcrun
require_command xmllint

[[ "$(basename -- "$APP_PATH")" == "TabList.app" ]] ||
  die "The exported application must be named TabList.app."
[[ "$(basename -- "$UPDATE_ARCHIVE")" == "TabList-${EXPECTED_MARKETING_VERSION}.zip" ]] ||
  die "The Sparkle archive name does not match the release version."
[[ "$(basename -- "$DMG_PATH")" == "TabList-${EXPECTED_MARKETING_VERSION}.dmg" ]] ||
  die "The disk-image name does not match the release version."
[[ "$(basename -- "$APPCAST_PATH")" == "appcast.xml" ]] ||
  die "The update feed must be named appcast.xml."

if [[ "$#" -eq 5 ]]; then
  EVIDENCE_DIR="$5"
  mkdir -p "$EVIDENCE_DIR"
else
  EVIDENCE_ROOT="${ROOT_DIR}/build/VerificationEvidence"
  mkdir -p "$EVIDENCE_ROOT"
  EVIDENCE_DIR="$(mktemp -d "${EVIDENCE_ROOT}/run.XXXXXX")"
fi

TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/tablist-verify.XXXXXX")"
DMG_MOUNT="${TEMP_DIR}/dmg"
DMG_ATTACHED=false

cleanup() {
  if [[ "$DMG_ATTACHED" == "true" ]]; then
    hdiutil detach "$DMG_MOUNT" -quiet >/dev/null 2>&1 || true
  fi
  rm -rf -- "$TEMP_DIR"
}
trap cleanup EXIT

run_and_record() {
  local output_path="$1"
  shift
  if "$@" >"$output_path" 2>&1; then
    cat "$output_path"
    return 0
  else
    local command_status=$?
    cat "$output_path" >&2
    return "$command_status"
  fi
}

read_plist_value() {
  local app_path="$1"
  local key="$2"
  /usr/libexec/PlistBuddy \
    -c "Print :${key}" \
    "${app_path}/Contents/Info.plist"
}

require_plist_value() {
  local app_path="$1"
  local key="$2"
  local expected="$3"
  local actual
  actual="$(read_plist_value "$app_path" "$key")"
  [[ "$actual" == "$expected" ]] ||
    die "${key} is '${actual}', expected '${expected}' in ${app_path}."
}

verify_arm64_only() {
  local app_path="$1"
  local label="$2"
  local output="${EVIDENCE_DIR}/${label}-architectures.txt"
  local count=0
  : > "$output"

  while IFS= read -r -d '' candidate; do
    if file -b "$candidate" | grep -q "Mach-O"; then
      local architectures
      local relative_path
      architectures="$(lipo -archs "$candidate")"
      relative_path="${candidate#"${app_path}/"}"
      printf '%s: %s\n' "$relative_path" "$architectures" >> "$output"
      [[ "$architectures" == "arm64" ]] ||
        die "${relative_path} contains '${architectures}', expected arm64 only."
      count=$((count + 1))
    fi
  done < <(find "$app_path" -type f -print0)

  (( count > 0 )) || die "No Mach-O files were found in ${app_path}."
}

verify_nested_signatures() {
  local app_path="$1"
  local label="$2"
  local output="${EVIDENCE_DIR}/${label}-nested-signatures.txt"
  local verified_count=0
  : > "$output"

  while IFS= read -r -d '' candidate; do
    if codesign --display "$candidate" >/dev/null 2>&1; then
      {
        printf '== %s ==\n' "${candidate#"${app_path}/"}"
        codesign --display --verbose=4 "$candidate" 2>&1
      } >> "$output"
      codesign --verify --strict --verbose=4 "$candidate" \
        >> "$output" 2>&1
      verified_count=$((verified_count + 1))
    fi
  done < <(
    find "${app_path}/Contents" \
      \( -type d \( -name '*.app' -o -name '*.framework' \
        -o -name '*.xpc' \) -o -type f -perm -111 \) \
      -print0
  )

  (( verified_count > 0 )) ||
    die "No signed executable code was found in ${app_path}."
}

verify_entitlements() {
  local app_path="$1"
  local label="$2"
  local entitlements="${EVIDENCE_DIR}/${label}-entitlements.plist"
  local diagnostics="${EVIDENCE_DIR}/${label}-entitlements.stderr.log"

  codesign --display --entitlements - "$app_path" \
    > "$entitlements" 2> "$diagnostics"
  if [[ -s "$entitlements" ]]; then
    plutil -lint "$entitlements" >/dev/null
    local forbidden_key
    for forbidden_key in \
      com.apple.security.app-sandbox \
      com.apple.security.get-task-allow
    do
      local forbidden_value
      forbidden_value="$(
        /usr/libexec/PlistBuddy \
          -c "Print :${forbidden_key}" \
          "$entitlements" 2>/dev/null || true
      )"
      [[ -z "$forbidden_value" || "$forbidden_value" == "false" ]] ||
        die "Forbidden release entitlement is enabled: ${forbidden_key}."
    done
  fi
}

verify_app_bundle() {
  local app_path="$1"
  local label="$2"
  local info_plist="${app_path}/Contents/Info.plist"
  local resources="${app_path}/Contents/Resources"
  local signature_metadata="${EVIDENCE_DIR}/${label}-codesign-metadata.txt"

  require_file "$info_plist"
  require_file "${resources}/LICENSE"
  require_file "${resources}/PRIVACY.md"
  require_file "${resources}/THIRD_PARTY_NOTICES.md"
  require_file "${resources}/Sparkle-LICENSE.txt"

  run_and_record \
    "${EVIDENCE_DIR}/${label}-codesign-verify.txt" \
    codesign --verify --deep --strict --verbose=4 "$app_path"
  codesign --display --verbose=4 "$app_path" \
    > "$signature_metadata" 2>&1

  local signed_identifier
  local signed_team
  local signed_authority
  signed_identifier="$(
    awk -F= '/^Identifier=/{print $2; exit}' "$signature_metadata"
  )"
  signed_team="$(
    awk -F= '/^TeamIdentifier=/{print $2; exit}' "$signature_metadata"
  )"
  signed_authority="$(
    awk -F= '/^Authority=/{print $2; exit}' "$signature_metadata"
  )"

  [[ "$signed_identifier" == "$EXPECTED_BUNDLE_IDENTIFIER" ]] ||
    die "Signed identifier '${signed_identifier}' is unexpected."
  [[ "$signed_team" == "$EXPECTED_DEVELOPMENT_TEAM" ]] ||
    die "Signed team '${signed_team}' is unexpected."
  [[ "$signed_authority" == "$EXPECTED_CODE_SIGN_IDENTITY" ]] ||
    die "Signing authority '${signed_authority}' is unexpected."
  grep -Eq '^CodeDirectory .*flags=.*\(.*runtime.*\)' \
    "$signature_metadata" ||
    die "The hardened runtime flag is missing from ${app_path}."

  require_plist_value \
    "$app_path" \
    CFBundleIdentifier \
    "$EXPECTED_BUNDLE_IDENTIFIER"
  require_plist_value \
    "$app_path" \
    CFBundleShortVersionString \
    "$EXPECTED_MARKETING_VERSION"
  require_plist_value \
    "$app_path" \
    CFBundleVersion \
    "$EXPECTED_BUILD_NUMBER"
  require_plist_value "$app_path" LSMinimumSystemVersion "15.0"
  require_plist_value "$app_path" LSUIElement "true"
  require_plist_value "$app_path" SUFeedURL "$EXPECTED_FEED_URL"
  require_plist_value "$app_path" SUEnableSystemProfiling "false"
  require_plist_value "$app_path" SUPublicEDKey "$SPARKLE_PUBLIC_ED_KEY"

  local executable_name
  executable_name="$(read_plist_value "$app_path" CFBundleExecutable)"
  require_file "${app_path}/Contents/MacOS/${executable_name}"

  verify_entitlements "$app_path" "$label"
  verify_arm64_only "$app_path" "$label"
  verify_nested_signatures "$app_path" "$label"
  run_and_record \
    "${EVIDENCE_DIR}/${label}-stapler.txt" \
    xcrun stapler validate "$app_path"
  run_and_record \
    "${EVIDENCE_DIR}/${label}-gatekeeper.txt" \
    spctl --assess --type execute --verbose=4 "$app_path"
}

verify_app_bundle "$APP_PATH" "exported-app"

DERIVED_PUBLIC_KEY="$(
  xcrun swift \
    "${ROOT_DIR}/Scripts/sparkle_public_key.swift" \
    "$SPARKLE_PRIVATE_ED_KEY_FILE"
)"
[[ "$DERIVED_PUBLIC_KEY" == "$SPARKLE_PUBLIC_ED_KEY" ]] ||
  die "The Sparkle private key does not derive the embedded public key."

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
  die "Appcast build '${APPCAST_BUILD_NUMBER}' is unexpected."
[[ "$APPCAST_MARKETING_VERSION" == "$EXPECTED_MARKETING_VERSION" ]] ||
  die "Appcast version '${APPCAST_MARKETING_VERSION}' is unexpected."
[[ "$APPCAST_DOWNLOAD_URL" == "$EXPECTED_DOWNLOAD_URL" ]] ||
  die "Appcast URL '${APPCAST_DOWNLOAD_URL}' is unexpected."
[[ "$APPCAST_LENGTH" == "$ARCHIVE_LENGTH" ]] ||
  die "Appcast length '${APPCAST_LENGTH}' does not match the ZIP."
[[ -n "$APPCAST_SIGNATURE" ]] ||
  die "The appcast enclosure is missing its Sparkle EdDSA signature."

SIGN_UPDATE="$(locate_sparkle_tool sign_update)"
run_and_record \
  "${EVIDENCE_DIR}/sparkle-signature.txt" \
  "$SIGN_UPDATE" \
    --verify \
    --ed-key-file - \
    "$UPDATE_ARCHIVE" \
    "$APPCAST_SIGNATURE" < "$SPARKLE_PRIVATE_ED_KEY_FILE"

ZIP_ROOT="${TEMP_DIR}/zip"
mkdir -p "$ZIP_ROOT"
ditto -x -k "$UPDATE_ARCHIVE" "$ZIP_ROOT"
ZIP_APP_COUNT="$(
  find "$ZIP_ROOT" -type d -name TabList.app -prune -print |
    wc -l | tr -d '[:space:]'
)"
[[ "$ZIP_APP_COUNT" == "1" ]] ||
  die "The Sparkle ZIP must contain exactly one TabList.app."
ZIP_APP="$(
  find "$ZIP_ROOT" -type d -name TabList.app -prune -print -quit
)"
verify_app_bundle "$ZIP_APP" "zip-app"

run_and_record \
  "${EVIDENCE_DIR}/dmg-codesign.txt" \
  codesign --verify --strict --verbose=4 "$DMG_PATH"
codesign --display --verbose=4 "$DMG_PATH" \
  > "${EVIDENCE_DIR}/dmg-codesign-metadata.txt" 2>&1
DMG_SIGNED_TEAM="$(
  awk -F= '/^TeamIdentifier=/{print $2; exit}' \
    "${EVIDENCE_DIR}/dmg-codesign-metadata.txt"
)"
DMG_SIGNED_AUTHORITY="$(
  awk -F= '/^Authority=/{print $2; exit}' \
    "${EVIDENCE_DIR}/dmg-codesign-metadata.txt"
)"
[[ "$DMG_SIGNED_TEAM" == "$EXPECTED_DEVELOPMENT_TEAM" ]] ||
  die "The DMG signing team is '${DMG_SIGNED_TEAM}', not the release team."
[[ "$DMG_SIGNED_AUTHORITY" == "$EXPECTED_CODE_SIGN_IDENTITY" ]] ||
  die "The DMG signing authority is unexpected."
run_and_record \
  "${EVIDENCE_DIR}/dmg-hdiutil-verify.txt" \
  hdiutil verify "$DMG_PATH"
run_and_record \
  "${EVIDENCE_DIR}/dmg-stapler.txt" \
  xcrun stapler validate "$DMG_PATH"
run_and_record \
  "${EVIDENCE_DIR}/dmg-gatekeeper.txt" \
  spctl --assess --type open \
    --context context:primary-signature \
    --verbose=4 \
    "$DMG_PATH"

mkdir -p "$DMG_MOUNT"
run_and_record \
  "${EVIDENCE_DIR}/dmg-attach.txt" \
  hdiutil attach \
    -readonly \
    -nobrowse \
    -mountpoint "$DMG_MOUNT" \
    "$DMG_PATH"
DMG_ATTACHED=true

DMG_APP_COUNT="$(
  find "$DMG_MOUNT" -type d -name TabList.app -prune -print |
    wc -l | tr -d '[:space:]'
)"
[[ "$DMG_APP_COUNT" == "1" ]] ||
  die "The DMG must contain exactly one TabList.app."
DMG_APP="$(
  find "$DMG_MOUNT" -type d -name TabList.app -prune -print -quit
)"
verify_app_bundle "$DMG_APP" "dmg-app"

require_file "${DMG_MOUNT}/Documentation/TabList-LICENSE.txt"
require_file "${DMG_MOUNT}/Documentation/PRIVACY.md"
require_file "${DMG_MOUNT}/Documentation/THIRD_PARTY_NOTICES.md"
require_file "${DMG_MOUNT}/Documentation/Sparkle-LICENSE.txt"
[[ -L "${DMG_MOUNT}/Applications" ]] ||
  die "The DMG must contain an Applications symlink."
[[ "$(readlink "${DMG_MOUNT}/Applications")" == "/Applications" ]] ||
  die "The DMG Applications symlink has an unexpected destination."

EXPORTED_CDHASH="$(
  awk -F= '/^CDHash=/{print $2; exit}' \
    "${EVIDENCE_DIR}/exported-app-codesign-metadata.txt"
)"
ZIP_CDHASH="$(
  awk -F= '/^CDHash=/{print $2; exit}' \
    "${EVIDENCE_DIR}/zip-app-codesign-metadata.txt"
)"
DMG_CDHASH="$(
  awk -F= '/^CDHash=/{print $2; exit}' \
    "${EVIDENCE_DIR}/dmg-app-codesign-metadata.txt"
)"
[[ -n "$EXPORTED_CDHASH" &&
   "$EXPORTED_CDHASH" == "$ZIP_CDHASH" &&
   "$EXPORTED_CDHASH" == "$DMG_CDHASH" ]] ||
  die "Exported, ZIP, and DMG application code hashes do not match."

ZIP_SHA256="$(
  shasum -a 256 "$UPDATE_ARCHIVE" | awk '{print $1}'
)"
DMG_SHA256="$(
  shasum -a 256 "$DMG_PATH" | awk '{print $1}'
)"
APPCAST_SHA256="$(
  shasum -a 256 "$APPCAST_PATH" | awk '{print $1}'
)"
ZIP_SIZE="$(stat -f '%z' "$UPDATE_ARCHIVE")"
DMG_SIZE="$(stat -f '%z' "$DMG_PATH")"
APPCAST_SIZE="$(stat -f '%z' "$APPCAST_PATH")"
SOURCE_COMMIT_LOWER="$(
  printf '%s' "$EXPECTED_SOURCE_COMMIT" | tr '[:upper:]' '[:lower:]'
)"

{
  printf '%s  %s\n' "$ZIP_SHA256" "$(basename -- "$UPDATE_ARCHIVE")"
  printf '%s  %s\n' "$DMG_SHA256" "$(basename -- "$DMG_PATH")"
  printf '%s  %s\n' "$APPCAST_SHA256" "$(basename -- "$APPCAST_PATH")"
} > "${EVIDENCE_DIR}/SHA256SUMS"

jq -n \
  --arg version "$EXPECTED_MARKETING_VERSION" \
  --arg buildNumber "$EXPECTED_BUILD_NUMBER" \
  --arg tag "$EXPECTED_TAG" \
  --arg sourceCommit "$SOURCE_COMMIT_LOWER" \
  --argjson prerelease "$EXPECTED_PRERELEASE" \
  --arg bundleIdentifier "$EXPECTED_BUNDLE_IDENTIFIER" \
  --arg teamIdentifier "$EXPECTED_DEVELOPMENT_TEAM" \
  --arg signingAuthority "$EXPECTED_CODE_SIGN_IDENTITY" \
  --arg feedURL "$EXPECTED_FEED_URL" \
  --arg cdHash "$EXPORTED_CDHASH" \
  --arg zipName "$(basename -- "$UPDATE_ARCHIVE")" \
  --arg zipSha256 "$ZIP_SHA256" \
  --argjson zipSize "$ZIP_SIZE" \
  --arg dmgName "$(basename -- "$DMG_PATH")" \
  --arg dmgSha256 "$DMG_SHA256" \
  --argjson dmgSize "$DMG_SIZE" \
  --arg appcastName "$(basename -- "$APPCAST_PATH")" \
  --arg appcastSha256 "$APPCAST_SHA256" \
  --argjson appcastSize "$APPCAST_SIZE" \
  --arg verifiedAt "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  '{
    schemaVersion: 1,
    result: "passed",
    version: $version,
    buildNumber: $buildNumber,
    tag: $tag,
    sourceCommit: $sourceCommit,
    prerelease: $prerelease,
    application: {
      bundleIdentifier: $bundleIdentifier,
      teamIdentifier: $teamIdentifier,
      signingAuthority: $signingAuthority,
      hardenedRuntime: true,
      sandboxed: false,
      getTaskAllow: false,
      architectures: ["arm64"],
      minimumSystemVersion: "15.0",
      feedURL: $feedURL,
      cdHash: $cdHash,
      stapled: true,
      gatekeeperAccepted: true
    },
    artifacts: {
      zip: {
        name: $zipName,
        sha256: $zipSha256,
        size: $zipSize,
        sparkleSignatureVerified: true
      },
      dmg: {
        name: $dmgName,
        sha256: $dmgSha256,
        size: $dmgSize,
        stapled: true,
        gatekeeperAccepted: true
      },
      appcast: {
        name: $appcastName,
        sha256: $appcastSha256,
        size: $appcastSize
      }
    },
    packagedCopiesMatchExportedCDHash: true,
    verifiedAt: $verifiedAt
  }' > "${EVIDENCE_DIR}/release-manifest.json"

jq empty "${EVIDENCE_DIR}/release-manifest.json"
note "Release verification passed; evidence is at ${EVIDENCE_DIR}"
