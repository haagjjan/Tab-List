#!/usr/bin/env bash

set -euo pipefail
source "$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/common.sh"

require_full_xcode
require_env NOTARY_KEY_PATH
require_env NOTARY_KEY_ID
require_env NOTARY_ISSUER_ID
require_file "$NOTARY_KEY_PATH"

[[ "$#" -eq 1 ]] || die "Usage: $0 <signed-app-or-dmg>"
ARTIFACT_PATH="$1"
[[ -e "$ARTIFACT_PATH" ]] || die "Artifact does not exist: $ARTIFACT_PATH"

SUBMISSION_PATH="$ARTIFACT_PATH"
TEMP_DIR=""

cleanup() {
  if [[ -n "$TEMP_DIR" && -d "$TEMP_DIR" ]]; then
    rm -rf -- "$TEMP_DIR"
  fi
}
trap cleanup EXIT

if [[ "$ARTIFACT_PATH" == *.app ]]; then
  require_directory "$ARTIFACT_PATH"
  codesign --verify --deep --strict --verbose=2 "$ARTIFACT_PATH"
  TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/tablist-notary.XXXXXX")"
  SUBMISSION_PATH="${TEMP_DIR}/TabList-notarization.zip"
  ditto -c -k --keepParent --sequesterRsrc "$ARTIFACT_PATH" "$SUBMISSION_PATH"
elif [[ "$ARTIFACT_PATH" != *.dmg ]]; then
  die "Only a signed .app bundle or .dmg is supported."
else
  codesign --verify --strict --verbose=2 "$ARTIFACT_PATH"
fi

note "Submitting $(basename -- "$ARTIFACT_PATH") to Apple notarization"
xcrun notarytool submit "$SUBMISSION_PATH" \
  --key "$NOTARY_KEY_PATH" \
  --key-id "$NOTARY_KEY_ID" \
  --issuer "$NOTARY_ISSUER_ID" \
  --wait

note "Stapling notarization ticket"
xcrun stapler staple "$ARTIFACT_PATH"
xcrun stapler validate "$ARTIFACT_PATH"

if [[ "$ARTIFACT_PATH" == *.app ]]; then
  spctl --assess --type execute --verbose=2 "$ARTIFACT_PATH"
else
  codesign --verify --strict --verbose=2 "$ARTIFACT_PATH"
  spctl --assess --type open --context context:primary-signature --verbose=2 "$ARTIFACT_PATH"
fi
