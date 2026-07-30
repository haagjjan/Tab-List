#!/usr/bin/env bash

set -euo pipefail
source "$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/common.sh"

require_full_xcode
generate_project

DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-${ROOT_DIR}/build/DerivedData}"
RESULT_BUNDLE_PATH="${RESULT_BUNDLE_PATH:-${ROOT_DIR}/build/TestResults.xcresult}"

mkdir -p "$(dirname -- "$RESULT_BUNDLE_PATH")"

note "Building the application, test bundles, and window fixture"
xcodebuild \
  test \
  -project "${ROOT_DIR}/TabList.xcodeproj" \
  -scheme TabList-CI \
  -configuration Debug \
  -destination "platform=macOS,arch=arm64" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  -resultBundlePath "$RESULT_BUNDLE_PATH" \
  COMPILER_INDEX_STORE_ENABLE=NO
