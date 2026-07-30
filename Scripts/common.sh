#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(CDPATH='' cd -- "${SCRIPT_DIR}/.." && pwd)"

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

note() {
  printf '==> %s\n' "$*"
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "Required command '$1' is not installed."
}

require_env() {
  local name="$1"
  [[ -n "${!name:-}" ]] || die "Required environment variable '$name' is not set."
}

require_file() {
  [[ -f "$1" ]] || die "Required file does not exist: $1"
}

require_directory() {
  [[ -d "$1" ]] || die "Required directory does not exist: $1"
}

require_full_xcode() {
  require_command xcode-select
  local developer_dir
  developer_dir="$(xcode-select -p 2>/dev/null || true)"
  [[ "$developer_dir" == *".app/Contents/Developer" ]] ||
    die "Full Xcode is required. Select it with: sudo xcode-select -s /Applications/Xcode.app/Contents/Developer"
  require_command xcodebuild
}

generate_project() {
  require_command xcodegen
  note "Generating TabList.xcodeproj from project.yml"
  (
    cd "$ROOT_DIR"
    xcodegen generate --spec project.yml
  )
}

locate_sparkle_tool() {
  local tool_name="$1"
  local search_root="${DERIVED_DATA_PATH:-${ROOT_DIR}/build/DerivedData}/SourcePackages"
  local candidate

  candidate="$(find "$search_root" -type f -path "*/Sparkle/bin/${tool_name}" -perm -111 -print -quit 2>/dev/null || true)"
  [[ -n "$candidate" ]] || die "Could not find Sparkle tool '${tool_name}' under ${search_root}. Resolve package dependencies first."
  printf '%s\n' "$candidate"
}

validate_version() {
  [[ "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z]+([.-][0-9A-Za-z]+)*)?$ ]] ||
    die "Version '$1' must use x.y.z syntax with an optional pre-release suffix."
}

validate_build_number() {
  [[ "$1" =~ ^[1-9][0-9]*$ ]] || die "Build number '$1' must be a positive integer."
}
