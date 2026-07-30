#!/usr/bin/env bash

set -euo pipefail
source "$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/common.sh"

[[ "$#" -eq 2 ]] ||
  die "Usage: $0 <new-build-number> <previous-appcast.xml>"

NEW_BUILD_NUMBER="$1"
PREVIOUS_APPCAST="$2"

validate_build_number "$NEW_BUILD_NUMBER"
require_file "$PREVIOUS_APPCAST"
require_command xmllint

xmllint --noout "$PREVIOUS_APPCAST"
PREVIOUS_BUILD_NUMBER="$(
  xmllint \
    --xpath \
    "string((//*[local-name()='item'])[1]/*[local-name()='version'][1])" \
    "$PREVIOUS_APPCAST"
)"
if [[ -z "$PREVIOUS_BUILD_NUMBER" ]]; then
  PREVIOUS_BUILD_NUMBER="$(
    xmllint \
      --xpath \
      "string((//*[local-name()='item']/*[local-name()='enclosure'])[1]/@*[local-name()='version'])" \
      "$PREVIOUS_APPCAST"
  )"
fi

[[ "$PREVIOUS_BUILD_NUMBER" =~ ^[1-9][0-9]*$ ]] ||
  die "The previous appcast does not contain a positive numeric sparkle:version."

new_decimal=$((10#${NEW_BUILD_NUMBER}))
previous_decimal=$((10#${PREVIOUS_BUILD_NUMBER}))
(( new_decimal > previous_decimal )) ||
  die "Build ${NEW_BUILD_NUMBER} must be greater than the latest published build ${PREVIOUS_BUILD_NUMBER}."

note "Build ${NEW_BUILD_NUMBER} is newer than published build ${PREVIOUS_BUILD_NUMBER}"
