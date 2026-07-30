#!/usr/bin/env bash

set -euo pipefail
source "$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/common.sh"

output_path="${1:-${ROOT_DIR}/build/CoreBenchmarkResults.json}"
mkdir -p "$(dirname -- "$output_path")"

note "Running optimized 100-window pure-core microbenchmarks"
(
  cd "$ROOT_DIR"
  swift run -c release TabListCoreBenchmarks --verify > "$output_path"
)

require_file "$output_path"
if command -v jq >/dev/null 2>&1; then
  jq -e 'all(.[]; .p95Milliseconds <= .verificationBudgetMilliseconds)' \
    "$output_path" >/dev/null
fi
note "Core benchmark evidence written to ${output_path}"
