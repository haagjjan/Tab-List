#!/usr/bin/env bash

set -euo pipefail
source "$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/common.sh"

require_command rg
require_command xcrun

validation_dir="$(mktemp -d "${TMPDIR:-/tmp}/tablist-clt-validation.XXXXXX")"
cleanup() {
  rm -rf -- "$validation_dir"
}
trap cleanup EXIT

sdk_path="$(xcrun --sdk macosx --show-sdk-path)"
target_triple="${TARGET_TRIPLE:-arm64-apple-macos15.0}"

core_sources=()
while IFS= read -r source; do
  core_sources+=("$source")
done < <(rg --files "$ROOT_DIR/Sources/TabListCore" -g '*.swift' | sort)

app_sources=()
while IFS= read -r source; do
  app_sources+=("$source")
done < <(rg --files "$ROOT_DIR/Sources/TabList" -g '*.swift' | sort)

fixture_sources=()
while IFS= read -r source; do
  fixture_sources+=("$source")
done < <(rg --files "$ROOT_DIR/Sources/WindowFixture" -g '*.swift' | sort)

(( ${#core_sources[@]} > 0 )) || die "No TabListCore sources found"
(( ${#app_sources[@]} > 0 )) || die "No TabList sources found"
(( ${#fixture_sources[@]} > 0 )) || die "No WindowFixture sources found"

swift_flags=(
  -sdk "$sdk_path"
  -target "$target_triple"
  -swift-version 6
  -strict-concurrency=complete
  -warnings-as-errors
)

note "Compiling TabListCore with strict Swift 6 concurrency"
xcrun swiftc \
  "${swift_flags[@]}" \
  -parse-as-library \
  -emit-module \
  -emit-module-path "$validation_dir/TabListCore.swiftmodule" \
  -module-name TabListCore \
  "${core_sources[@]}"

note "Type-checking the complete Debug application source"
xcrun swiftc \
  "${swift_flags[@]}" \
  -D DEBUG \
  -typecheck \
  -I "$validation_dir" \
  -module-name TabList \
  "${app_sources[@]}"

note "Type-checking the complete Release application source"
xcrun swiftc \
  "${swift_flags[@]}" \
  -typecheck \
  -I "$validation_dir" \
  -module-name TabList \
  "${app_sources[@]}"

note "Type-checking the compatibility fixture"
xcrun swiftc \
  "${swift_flags[@]}" \
  -D DEBUG \
  -typecheck \
  -module-name WindowFixture \
  "${fixture_sources[@]}"

note "Command Line Tools source validation passed"
