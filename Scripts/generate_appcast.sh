#!/usr/bin/env bash

set -euo pipefail
source "$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/common.sh"

[[ "$#" -eq 1 ]] || die "Usage: $0 <directory-containing-only-sparkle-update-archives>"
UPDATES_DIR="$1"
require_directory "$UPDATES_DIR"
require_env SPARKLE_PRIVATE_ED_KEY_FILE
require_file "$SPARKLE_PRIVATE_ED_KEY_FILE"

DOWNLOAD_URL_PREFIX="${DOWNLOAD_URL_PREFIX:-https://github.com/haagjjan/Tab-List/releases/latest/download/}"
GENERATE_APPCAST="$(locate_sparkle_tool generate_appcast)"

shopt -s nullglob
archives=("$UPDATES_DIR"/*.zip "$UPDATES_DIR"/*.aar "$UPDATES_DIR"/*.tar.xz)
shopt -u nullglob
[[ "${#archives[@]}" -gt 0 ]] || die "No Sparkle update archive found in ${UPDATES_DIR}."

note "Generating EdDSA-signed Sparkle appcast"
"$GENERATE_APPCAST" \
  --ed-key-file - \
  --download-url-prefix "$DOWNLOAD_URL_PREFIX" \
  "$UPDATES_DIR" < "$SPARKLE_PRIVATE_ED_KEY_FILE"

require_file "${UPDATES_DIR}/appcast.xml"
note "Generated ${UPDATES_DIR}/appcast.xml"
