#!/usr/bin/env bash
# FORGE Audit Trail Verification — validate audit integrity (Spec 103)
# Usage: forge-audit-verify.sh [--spec NNN] [--verbose]
set -euo pipefail

FORGE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_DIR="$(cd "${FORGE_DIR}/.." && pwd)"

source "${FORGE_DIR}/lib/logging.sh"
source "${FORGE_DIR}/lib/audit-trail.sh"

forge_log_init "forge-audit-verify"

SPEC_FILTER=""
VERBOSE=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --spec) SPEC_FILTER="$2"; shift 2 ;;
    --verbose) VERBOSE=true; shift ;;
    -h|--help)
      echo "Usage: forge-audit-verify.sh [--spec NNN] [--verbose]"
      echo ""
      echo "Verifies the Lane B audit trail integrity:"
      echo "  1. Validates GPG signatures on signed commits and tags"
      echo "  2. Verifies manifest hashes match current file contents"
      echo "  3. Reports any tampering or missing signatures"
      echo ""
      echo "Options:"
      echo "  --spec NNN    Verify only the specified spec (default: all)"
      echo "  --verbose     Show detailed output for each check"
      echo "  -h, --help    Show this help"
      exit 0
      ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

# --- Check Lane B ---
if ! forge_audit_trail_is_lane_b "$PROJECT_DIR"; then
  echo "Lane A project — no audit trail to verify."
  exit 0
fi

MANIFEST_FILE="${PROJECT_DIR}/docs/compliance/audit-manifest.json"
PASS_COUNT=0
FAIL_COUNT=0
WARN_COUNT=0

report_pass() {
  PASS_COUNT=$((PASS_COUNT + 1))
  echo "  PASS: $1"
}

report_fail() {
  FAIL_COUNT=$((FAIL_COUNT + 1))
  echo "  FAIL: $1" >&2
}

report_warn() {
  WARN_COUNT=$((WARN_COUNT + 1))
  echo "  WARN: $1"
}

echo "=== FORGE Audit Trail Verification ==="
echo ""

# --- 1. Check manifest exists ---
echo "--- Manifest Integrity ---"
if [[ ! -f "$MANIFEST_FILE" ]]; then
  report_fail "Audit manifest not found: ${MANIFEST_FILE}"
  echo ""
  echo "Results: ${PASS_COUNT} passed, ${FAIL_COUNT} failed, ${WARN_COUNT} warnings"
  exit 1
fi
report_pass "Audit manifest found"

# --- 2. Validate manifest is parseable JSON ---
if ! python3 -c "import json; json.load(open('${MANIFEST_FILE}'))" 2>/dev/null; then
  report_fail "Audit manifest is not valid JSON"
  echo ""
  echo "Results: ${PASS_COUNT} passed, ${FAIL_COUNT} failed, ${WARN_COUNT} warnings"
  exit 1
fi
report_pass "Audit manifest is valid JSON"

# --- 3. Verify spec hashes ---
echo ""
echo "--- Spec File Integrity ---"

# Extract entries from manifest using python3 (portable JSON parsing)
ENTRY_COUNT="$(python3 -c "
import json, sys
data = json.load(open('${MANIFEST_FILE}'))
if '${SPEC_FILTER}':
    data = [e for e in data if e.get('spec_id') == '${SPEC_FILTER}']
print(len(data))
")"

if [[ "$ENTRY_COUNT" == "0" ]]; then
  if [[ -n "$SPEC_FILTER" ]]; then
    echo "  No manifest entries found for spec ${SPEC_FILTER}."
  else
    echo "  No manifest entries found."
  fi
else
  # Iterate over manifest entries
  python3 -c "
import json, sys
data = json.load(open('${MANIFEST_FILE}'))
if '${SPEC_FILTER}':
    data = [e for e in data if e.get('spec_id') == '${SPEC_FILTER}']
for e in data:
    spec_id = e.get('spec_id', 'unknown')
    spec_hash = e.get('spec_hash', {})
    fname = spec_hash.get('file', '')
    expected = spec_hash.get('sha256', '')
    print(f'{spec_id}|{fname}|{expected}')
" | while IFS='|' read -r sid sfile expected_hash; do
    SPEC_PATH="${PROJECT_DIR}/docs/specs/${sfile}"
    if [[ ! -f "$SPEC_PATH" ]]; then
      report_fail "Spec ${sid}: file missing — ${sfile}"
      continue
    fi
    ACTUAL_HASH="$(sha256sum "$SPEC_PATH" | cut -d' ' -f1)"
    if [[ "$ACTUAL_HASH" == "$expected_hash" ]]; then
      report_pass "Spec ${sid}: hash matches"
      if $VERBOSE; then
        echo "    SHA-256: ${ACTUAL_HASH}"
      fi
    else
      report_fail "Spec ${sid}: HASH MISMATCH — file has been modified since closure"
      if $VERBOSE; then
        echo "    Expected: ${expected_hash}"
        echo "    Actual:   ${ACTUAL_HASH}"
      fi
    fi
  done
fi

# --- 4. Verify signed tags ---
echo ""
echo "--- Signed Tags ---"

# Find spec closure tags
TAG_PATTERN="spec-"
if [[ -n "$SPEC_FILTER" ]]; then
  TAG_PATTERN="spec-${SPEC_FILTER}-closed"
fi

TAGS_FOUND=false
while IFS= read -r tag; do
  if [[ -z "$tag" ]]; then continue; fi
  TAGS_FOUND=true

  # Check if tag has a valid GPG signature
  if git tag -v "$tag" &>/dev/null; then
    report_pass "Tag ${tag}: valid GPG signature"
  else
    # Check if it's an annotated tag (unsigned)
    TAG_TYPE="$(git cat-file -t "$tag" 2>/dev/null || echo "unknown")"
    if [[ "$TAG_TYPE" == "tag" ]]; then
      report_warn "Tag ${tag}: annotated but unsigned (GPG was not configured at closure)"
    else
      report_fail "Tag ${tag}: invalid or missing signature"
    fi
  fi
done < <(git tag -l "${TAG_PATTERN}*" 2>/dev/null)

if ! $TAGS_FOUND; then
  if [[ -n "$SPEC_FILTER" ]]; then
    echo "  No closure tags found for spec ${SPEC_FILTER}."
  else
    echo "  No closure tags found."
  fi
fi

# --- 5. Verify signed commits ---
echo ""
echo "--- Signed Commits ---"

# Check commits that reference spec closures
if forge_audit_trail_gpg_available; then
  # Look for closure commits in the manifest
  python3 -c "
import json
data = json.load(open('${MANIFEST_FILE}'))
if '${SPEC_FILTER}':
    data = [e for e in data if e.get('spec_id') == '${SPEC_FILTER}']
for e in data:
    print(e.get('spec_id', ''), e.get('commit_hash', ''))
" | while IFS=' ' read -r sid chash; do
    if [[ -z "$chash" || "$chash" == "unknown" ]]; then continue; fi
    # Verify the commit exists and check signature
    if ! git cat-file -e "$chash" 2>/dev/null; then
      report_warn "Spec ${sid}: closure commit ${chash:0:8} not found (may have been rebased)"
      continue
    fi
    SIG_STATUS="$(git log --format='%G?' -1 "$chash" 2>/dev/null || echo "N")"
    case "$SIG_STATUS" in
      G) report_pass "Spec ${sid}: commit ${chash:0:8} has valid GPG signature" ;;
      U) report_warn "Spec ${sid}: commit ${chash:0:8} has untrusted GPG signature" ;;
      N) report_warn "Spec ${sid}: commit ${chash:0:8} is unsigned" ;;
      *) report_warn "Spec ${sid}: commit ${chash:0:8} signature status: ${SIG_STATUS}" ;;
    esac
  done
else
  echo "  GPG not configured — skipping commit signature verification."
  report_warn "GPG signing not available — cannot verify commit signatures"
fi

# --- Summary ---
echo ""
echo "=== Verification Summary ==="
echo "Passed:   ${PASS_COUNT}"
echo "Failed:   ${FAIL_COUNT}"
echo "Warnings: ${WARN_COUNT}"

if (( FAIL_COUNT > 0 )); then
  echo ""
  echo "AUDIT TRAIL INTEGRITY: FAILED"
  echo "Action required: investigate FAIL items above."
  exit 1
else
  echo ""
  if (( WARN_COUNT > 0 )); then
    echo "AUDIT TRAIL INTEGRITY: PASSED (with warnings)"
  else
    echo "AUDIT TRAIL INTEGRITY: PASSED"
  fi
  exit 0
fi
