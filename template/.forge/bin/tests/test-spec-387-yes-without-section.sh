#!/usr/bin/env bash
# test-spec-387-yes-without-section — AC4.
# When the spec body lacks a ## Safety Enforcement section, the validator returns 2
# with the canonical R2e error message.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FORGE_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
# shellcheck source=/dev/null
source "${FORGE_DIR}/lib/safety-config.sh"

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
spec="${TMP}/spec-999.md"
cat > "$spec" << 'EOF'
# Spec 999 — fixture without Safety Enforcement

## Scope
Body without enforcement section.

## Implementation Summary
(empty)
EOF

set +e
err="$(safety_config_validate_section "$spec" "$TMP" 2>&1 1>/dev/null)"
rc=$?
set -e

if (( rc != 2 )); then
  echo "FAIL: expected exit 2, got $rc" >&2
  exit 1
fi
if [[ "$err" != *"Safety enforcement section incomplete or missing"* ]]; then
  echo "FAIL: unexpected error message: $err" >&2
  exit 1
fi
echo "PASS: missing section produces exit 2 + R2e message"
exit 0
