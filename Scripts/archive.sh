#!/usr/bin/env bash

set -euo pipefail
source "$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/common.sh"

require_full_xcode
require_env DEVELOPMENT_TEAM
require_env CODE_SIGN_IDENTITY
require_env MARKETING_VERSION
require_env BUILD_NUMBER
require_env SPARKLE_PUBLIC_ED_KEY

validate_version "$MARKETING_VERSION"
validate_build_number "$BUILD_NUMBER"
generate_project

ARCHIVE_PATH="${ARCHIVE_PATH:-${ROOT_DIR}/build/TabList.xcarchive}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-${ROOT_DIR}/build/DerivedData}"
mkdir -p "$(dirname -- "$ARCHIVE_PATH")"

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
note "Archive created at ${ARCHIVE_PATH}"
