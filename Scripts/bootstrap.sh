#!/usr/bin/env bash

set -euo pipefail
source "$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/common.sh"

require_full_xcode
generate_project

note "Resolving Swift package dependencies"
xcodebuild \
  -resolvePackageDependencies \
  -project "${ROOT_DIR}/TabList.xcodeproj" \
  -scheme TabList \
  -derivedDataPath "${DERIVED_DATA_PATH:-${ROOT_DIR}/build/DerivedData}"

note "Bootstrap complete"
xcodebuild -version
swift --version
