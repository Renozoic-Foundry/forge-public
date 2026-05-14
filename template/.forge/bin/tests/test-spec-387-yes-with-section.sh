#!/usr/bin/env bash
# test-spec-387-yes-with-section — AC5.
# When the spec body has a complete ## Safety Enforcement section, the validator returns 0.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FORGE_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
# shellcheck source=/dev/null
source "${FORGE_DIR}/lib/safety-config.sh"

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

# Build a synthetic repo root with the referenced files actually existing.
mkdir -p "${TMP}/src" "${TMP}/tests" "${TMP}/docs/specs"
echo "exit 0" > "${TMP}/src/foo.sh"
echo "exit 0" > "${TMP}/tests/test-foo.sh"

spec="${TMP}/docs/specs/999-fixture.md"
cat > "$spec" << 'EOF'
# Spec 999 — fixture with valid Safety Enforcement

## Safety Enforcement

Enforcement code path: src/foo.sh::do_thing
Negative-path test: tests/test-foo.sh::test_rejects_unsafe
Validates that unsafe input is rejected before mutation.

## Implementation Summary
(empty)
EOF

if safety_config_validate_section "$spec" "$TMP"; then
  echo "PASS: complete section accepted by validator"
  exit 0
fi
echo "FAIL: complete section rejected" >&2
exit 1
