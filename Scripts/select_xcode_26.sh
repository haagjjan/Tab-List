#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

[[ "$(uname -m)" == "arm64" ]] ||
  die "Tab-List requires an Apple Silicon (arm64) development host."

candidates=()
if [[ -n "${XCODE_26_DEVELOPER_DIR:-}" ]]; then
  candidates+=("${XCODE_26_DEVELOPER_DIR}")
fi
candidates+=(
  "/Applications/Xcode_26.6.app/Contents/Developer"
  "/Applications/Xcode_26.5.app/Contents/Developer"
  "/Applications/Xcode_26.4.1.app/Contents/Developer"
  "/Applications/Xcode_26.4.app/Contents/Developer"
  "/Applications/Xcode_26.3.app/Contents/Developer"
  "/Applications/Xcode_26.2.app/Contents/Developer"
  "/Applications/Xcode_26.1.1.app/Contents/Developer"
  "/Applications/Xcode_26.1.app/Contents/Developer"
  "/Applications/Xcode_26.0.1.app/Contents/Developer"
  "/Applications/Xcode_26.0.app/Contents/Developer"
  "/Applications/Xcode.app/Contents/Developer"
)

selected=""
for candidate in "${candidates[@]}"; do
  xcodebuild_path="${candidate}/usr/bin/xcodebuild"
  [[ -x "$xcodebuild_path" ]] || continue
  version="$("$xcodebuild_path" -version | head -n 1)"
  if [[ "$version" == "Xcode 26."* ]]; then
    selected="$candidate"
    break
  fi
done

[[ -n "$selected" ]] ||
  die "No full Xcode 26 installation was found. Set XCODE_26_DEVELOPER_DIR to its Contents/Developer directory."

sudo xcode-select -s "$selected"

xcode_version="$(xcodebuild -version | head -n 1)"
swift_version="$(xcrun swift --version | head -n 1)"
[[ "$xcode_version" == "Xcode 26."* ]] ||
  die "Selected developer directory reported '${xcode_version}', not Xcode 26.x."
[[ "$swift_version" == *"Swift version 6.2"* ]] ||
  die "Selected Xcode reported '${swift_version}', not Swift 6.2."

note "Using ${xcode_version} from ${selected}"
note "${swift_version}"
