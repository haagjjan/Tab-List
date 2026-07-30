#!/usr/bin/env bash

set -euo pipefail
source "$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/common.sh"

require_full_xcode
require_env NOTARY_KEY_PATH
require_env NOTARY_KEY_ID
require_env NOTARY_ISSUER_ID
require_file "$NOTARY_KEY_PATH"
require_command codesign
require_command ditto
require_command jq
require_command shasum
require_command spctl
require_command xcrun

[[ "$#" -eq 1 ]] || die "Usage: $0 <signed-app-or-dmg>"
ARTIFACT_PATH="$1"
[[ -e "$ARTIFACT_PATH" ]] || die "Artifact does not exist: $ARTIFACT_PATH"

SUBMISSION_PATH="$ARTIFACT_PATH"
TEMP_DIR=""
ARTIFACT_TYPE=""

cleanup() {
  if [[ -n "$TEMP_DIR" && -d "$TEMP_DIR" ]]; then
    rm -rf -- "$TEMP_DIR"
  fi
}
trap cleanup EXIT

if [[ "$ARTIFACT_PATH" == *.app ]]; then
  ARTIFACT_TYPE="app"
  require_directory "$ARTIFACT_PATH"
  TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/tablist-notary.XXXXXX")"
  SUBMISSION_PATH="${TEMP_DIR}/TabList-notarization.zip"
elif [[ "$ARTIFACT_PATH" != *.dmg ]]; then
  die "Only a signed .app bundle or .dmg is supported."
else
  ARTIFACT_TYPE="dmg"
fi

if [[ -n "${NOTARIZATION_EVIDENCE_DIR:-}" ]]; then
  EVIDENCE_DIR="$NOTARIZATION_EVIDENCE_DIR"
  mkdir -p "$EVIDENCE_DIR"
else
  EVIDENCE_ROOT="${ROOT_DIR}/build/NotarizationEvidence"
  mkdir -p "$EVIDENCE_ROOT"
  EVIDENCE_DIR="$(mktemp -d "${EVIDENCE_ROOT}/${ARTIFACT_TYPE}.XXXXXX")"
fi

run_and_record() {
  local output_path="$1"
  shift
  if "$@" >"$output_path" 2>&1; then
    cat "$output_path"
    return 0
  else
    local command_status=$?
    cat "$output_path" >&2
    return "$command_status"
  fi
}

if [[ "$ARTIFACT_TYPE" == "app" ]]; then
  run_and_record \
    "${EVIDENCE_DIR}/codesign-preflight.txt" \
    codesign --verify --deep --strict --verbose=4 "$ARTIFACT_PATH"
  ditto -c -k --keepParent --sequesterRsrc \
    "$ARTIFACT_PATH" \
    "$SUBMISSION_PATH"
else
  run_and_record \
    "${EVIDENCE_DIR}/codesign-preflight.txt" \
    codesign --verify --strict --verbose=4 "$ARTIFACT_PATH"
fi

SUBMISSION_SHA256="$(
  shasum -a 256 "$SUBMISSION_PATH" | awk '{print $1}'
)"
printf '%s  %s\n' \
  "$SUBMISSION_SHA256" \
  "$(basename -- "$SUBMISSION_PATH")" \
  > "${EVIDENCE_DIR}/submission.sha256"

note "Submitting $(basename -- "$ARTIFACT_PATH") to Apple notarization"
set +e
xcrun notarytool submit "$SUBMISSION_PATH" \
  --key "$NOTARY_KEY_PATH" \
  --key-id "$NOTARY_KEY_ID" \
  --issuer "$NOTARY_ISSUER_ID" \
  --wait \
  --output-format json \
  > "${EVIDENCE_DIR}/submission.json" \
  2> "${EVIDENCE_DIR}/submission.stderr.log"
SUBMIT_STATUS=$?
set -e

if ! jq empty "${EVIDENCE_DIR}/submission.json" >/dev/null 2>&1; then
  jq -n \
    --arg artifactType "$ARTIFACT_TYPE" \
    --arg artifactName "$(basename -- "$ARTIFACT_PATH")" \
    --arg submissionSha256 "$SUBMISSION_SHA256" \
    --arg verifiedAt "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '{
      schemaVersion: 1,
      result: "failed",
      artifactType: $artifactType,
      artifactName: $artifactName,
      submissionID: null,
      status: "invalid-json",
      submissionSha256: $submissionSha256,
      verifiedAt: $verifiedAt
    }' > "${EVIDENCE_DIR}/summary.json"
  cat "${EVIDENCE_DIR}/submission.stderr.log" >&2
  die "notarytool did not produce valid JSON evidence."
fi

SUBMISSION_ID="$(
  jq -r '.id // empty' "${EVIDENCE_DIR}/submission.json"
)"
NOTARY_STATUS="$(
  jq -r '.status // empty' "${EVIDENCE_DIR}/submission.json"
)"
jq '{id, status, message}' "${EVIDENCE_DIR}/submission.json"

LOG_STATUS=1
if [[ -n "$SUBMISSION_ID" ]]; then
  for attempt in 1 2 3 4 5; do
    set +e
    xcrun notarytool log "$SUBMISSION_ID" \
      --key "$NOTARY_KEY_PATH" \
      --key-id "$NOTARY_KEY_ID" \
      --issuer "$NOTARY_ISSUER_ID" \
      > "${EVIDENCE_DIR}/notary-log.json" \
      2> "${EVIDENCE_DIR}/notary-log.stderr.log"
    LOG_STATUS=$?
    set -e
    if (( LOG_STATUS == 0 )) &&
       jq empty "${EVIDENCE_DIR}/notary-log.json" >/dev/null 2>&1; then
      break
    fi
    LOG_STATUS=1
    note "Notary log is not available yet (attempt ${attempt}/5)."
    sleep 2
  done
  if (( LOG_STATUS != 0 )); then
    note "Notary log retrieval failed; stderr was preserved as evidence."
  fi
fi

if (( SUBMIT_STATUS != 0 || LOG_STATUS != 0 )) ||
   [[ "$NOTARY_STATUS" != "Accepted" ]]; then
  jq -n \
    --arg artifactType "$ARTIFACT_TYPE" \
    --arg artifactName "$(basename -- "$ARTIFACT_PATH")" \
    --arg submissionID "$SUBMISSION_ID" \
    --arg status "$NOTARY_STATUS" \
    --arg submissionSha256 "$SUBMISSION_SHA256" \
    --arg verifiedAt "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '{
      schemaVersion: 1,
      result: "failed",
      artifactType: $artifactType,
      artifactName: $artifactName,
      submissionID: $submissionID,
      status: $status,
      submissionSha256: $submissionSha256,
      verifiedAt: $verifiedAt
    }' > "${EVIDENCE_DIR}/summary.json"
  cat "${EVIDENCE_DIR}/submission.stderr.log" >&2
  die "Apple notarization was not accepted. Evidence: ${EVIDENCE_DIR}"
fi

note "Stapling notarization ticket"
run_and_record \
  "${EVIDENCE_DIR}/stapler-staple.txt" \
  xcrun stapler staple "$ARTIFACT_PATH"
run_and_record \
  "${EVIDENCE_DIR}/stapler-validate.txt" \
  xcrun stapler validate "$ARTIFACT_PATH"

if [[ "$ARTIFACT_TYPE" == "app" ]]; then
  run_and_record \
    "${EVIDENCE_DIR}/codesign-final.txt" \
    codesign --verify --deep --strict --verbose=4 "$ARTIFACT_PATH"
  run_and_record \
    "${EVIDENCE_DIR}/gatekeeper.txt" \
    spctl --assess --type execute --verbose=4 "$ARTIFACT_PATH"
  FINAL_SHA256=""
  FINAL_CDHASH="$(
    codesign --display --verbose=4 "$ARTIFACT_PATH" 2>&1 |
      awk -F= '/^CDHash=/{print $2; exit}'
  )"
else
  run_and_record \
    "${EVIDENCE_DIR}/codesign-final.txt" \
    codesign --verify --strict --verbose=4 "$ARTIFACT_PATH"
  run_and_record \
    "${EVIDENCE_DIR}/gatekeeper.txt" \
    spctl --assess --type open \
      --context context:primary-signature \
      --verbose=4 \
      "$ARTIFACT_PATH"
  FINAL_SHA256="$(
    shasum -a 256 "$ARTIFACT_PATH" | awk '{print $1}'
  )"
  FINAL_CDHASH=""
fi

NOTARY_LOG_SHA256=""
if [[ -f "${EVIDENCE_DIR}/notary-log.json" ]]; then
  NOTARY_LOG_SHA256="$(
    shasum -a 256 "${EVIDENCE_DIR}/notary-log.json" |
      awk '{print $1}'
  )"
fi

jq -n \
  --arg artifactType "$ARTIFACT_TYPE" \
  --arg artifactName "$(basename -- "$ARTIFACT_PATH")" \
  --arg submissionID "$SUBMISSION_ID" \
  --arg status "$NOTARY_STATUS" \
  --arg submissionSha256 "$SUBMISSION_SHA256" \
  --arg finalSha256 "$FINAL_SHA256" \
  --arg finalCDHash "$FINAL_CDHASH" \
  --arg notaryLogSha256 "$NOTARY_LOG_SHA256" \
  --arg verifiedAt "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  '{
    schemaVersion: 1,
    result: "passed",
    artifactType: $artifactType,
    artifactName: $artifactName,
    submissionID: $submissionID,
    status: $status,
    submissionSha256: $submissionSha256,
    finalSha256: (if $finalSha256 == "" then null else $finalSha256 end),
    finalCDHash: (if $finalCDHash == "" then null else $finalCDHash end),
    notaryLogSha256: (
      if $notaryLogSha256 == "" then null else $notaryLogSha256 end
    ),
    stapled: true,
    gatekeeperAccepted: true,
    verifiedAt: $verifiedAt
  }' > "${EVIDENCE_DIR}/summary.json"

note "Notarization evidence preserved at ${EVIDENCE_DIR}"
