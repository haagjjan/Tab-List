#!/usr/bin/env bash

set -euo pipefail

readonly bundle_identifier="com.haagjjan.TabList"

if /usr/bin/pgrep -x TabList >/dev/null 2>&1; then
  echo "Quit the running Tab-List Debug build, then run this script again." >&2
  exit 1
fi

/usr/bin/tccutil reset Accessibility "$bundle_identifier"

echo "Reset Accessibility permission for $bundle_identifier."
echo "Run Tab-List from Xcode again and choose Request Accessibility."
