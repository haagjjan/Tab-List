#!/usr/bin/env bash

set -euo pipefail
source "$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/common.sh"

require_full_xcode
generate_project

DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-${ROOT_DIR}/build/DerivedData}"
if [[ -z "${RESULT_BUNDLE_PATH:-}" ]]; then
  RESULT_BUNDLE_ROOT="${RESULT_BUNDLE_DIRECTORY:-${ROOT_DIR}/build/TestResults}"
  mkdir -p "$RESULT_BUNDLE_ROOT"
  RESULT_BUNDLE_DIRECTORY="$(
    mktemp -d "${RESULT_BUNDLE_ROOT}/run.XXXXXX"
  )"
  RESULT_BUNDLE_PATH="${RESULT_BUNDLE_DIRECTORY}/TabListTests.xcresult"
elif [[ -e "$RESULT_BUNDLE_PATH" ]]; then
  RESULT_BUNDLE_BASE="${RESULT_BUNDLE_PATH%.xcresult}"
  RESULT_BUNDLE_PATH="$(
    mktemp -d "${RESULT_BUNDLE_BASE}.XXXXXX"
  ).xcresult"
  rmdir "${RESULT_BUNDLE_PATH%.xcresult}"
  note "Requested result bundle already exists; using ${RESULT_BUNDLE_PATH}"
fi

mkdir -p "$(dirname -- "$RESULT_BUNDLE_PATH")"
note "Test result bundle: ${RESULT_BUNDLE_PATH}"

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
