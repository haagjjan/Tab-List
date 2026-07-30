#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

[[ "$(uname -m)" == "arm64" ]] ||
  die "Tab-List requires an Apple Silicon (arm64) development host."

candidates=()
if [[ -n "${XCODE_26_DEVELOPER_DIR:-}" ]]; then
  candidates+=("${XCODE_26_DEVELOPER_DIR}")
fi
candidates+=(
  "/Applications/Xcode_26.9.app/Contents/Developer"
  "/Applications/Xcode_26.8.app/Contents/Developer"
  "/Applications/Xcode_26.7.app/Contents/Developer"
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

while IFS= read -r -d '' application; do
  candidates+=("${application}/Contents/Developer")
done < <(
  find /Applications \
    -maxdepth 1 \
    -type d \
    -name 'Xcode*.app' \
    -print0 2>/dev/null
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

if [[ "$(xcode-select -p 2>/dev/null || true)" != "$selected" ]]; then
  sudo xcode-select -s "$selected"
fi

xcode_version="$(xcodebuild -version | head -n 1)"
swift_version="$(xcrun swift --version | head -n 1)"
sdk_version="$(xcrun --sdk macosx --show-sdk-version)"
[[ "$xcode_version" == "Xcode 26."* ]] ||
  die "Selected developer directory reported '${xcode_version}', not Xcode 26.x."
[[ "$swift_version" == *"Swift version 6.2"* ]] ||
  die "Selected Xcode reported '${swift_version}', not Swift 6.2."
[[ "$sdk_version" == "26."* ]] ||
  die "Selected Xcode reported macOS SDK '${sdk_version}', not 26.x."
xcodebuild -checkFirstLaunchStatus >/dev/null 2>&1 ||
  die "Xcode first-launch setup is incomplete. Run: sudo xcodebuild -runFirstLaunch"

note "Using ${xcode_version} from ${selected}"
note "${swift_version}"
note "macOS SDK ${sdk_version}; deployment target remains macOS 15.0"
