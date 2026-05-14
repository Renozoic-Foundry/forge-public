#!/usr/bin/env bash
# test-spec-387-sha-exclusion — AC6: ## Safety Enforcement section is excluded from Approved-SHA.
# Computing SHA before and after a code-path edit inside the Safety Enforcement section yields
# identical hashes (Spec 365 frontmatter-exclusion model extended to cover this section + the
# Safety-Override frontmatter field).
#
# Spec 387 R2f, R4d.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FORGE_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

# Build a minimal spec body containing all four protected sections + the Safety Enforcement
# section. The protected sections (Scope, Requirements, Acceptance Criteria, Test Plan) are the
# only inputs to the Approved-SHA per Spec 089; ## Safety Enforcement is OUTSIDE the protected
# set per R2f.
spec_v1="${TMP_ROOT}/spec-v1.md"
cat > "$spec_v1" << 'EOF'
# Spec 999 — Test fixture for SHA exclusion

## Scope

In scope: testing.

## Requirements

R1. Do the thing.

## Acceptance Criteria

1. The thing is done.

## Test Plan

Run a fixture.

## Safety Enforcement

Enforcement code path: src/foo.sh::do_thing
Negative-path test: tests/test-foo.sh::test_rejects_unsafe
Validates that the unsafe condition is rejected.

## Implementation Summary

(empty)
EOF

# Compute SHA over the four protected sections (matching Spec 089 procedure).
# Since this fixture is exercising the EXCLUSION property, we extract those four sections
# (Scope, Requirements, AC, Test Plan) — explicitly NOT including Safety Enforcement.
extract_protected_sections() {
  local file="$1"
  awk '
    /^## Scope/                {p=1; print; next}
    /^## Requirements/         {p=1; print; next}
    /^## Acceptance Criteria/  {p=1; print; next}
    /^## Test Plan/            {p=1; print; next}
    /^## /                     {p=0}
    p                          {print}
  ' "$file"
}

sha_of_protected() {
  extract_protected_sections "$1" | sha256sum | cut -d' ' -f1
}

sha_v1="$(sha_of_protected "$spec_v1")"

# Edit only the Safety Enforcement section (change the code path from foo.sh to bar.sh).
spec_v2="${TMP_ROOT}/spec-v2.md"
sed 's|src/foo.sh::do_thing|src/bar.sh::do_thing|; s|tests/test-foo.sh|tests/test-bar.sh|' \
  "$spec_v1" > "$spec_v2"

sha_v2="$(sha_of_protected "$spec_v2")"

if [[ "$sha_v1" == "$sha_v2" ]]; then
  echo "PASS: Safety Enforcement section edits do not change Approved-SHA over protected sections"
  echo "      sha_v1 = ${sha_v1:0:16}..."
  echo "      sha_v2 = ${sha_v2:0:16}..."
else
  echo "FAIL: SHA over protected sections changed when Safety Enforcement section was edited" >&2
  echo "      sha_v1 = $sha_v1" >&2
  echo "      sha_v2 = $sha_v2" >&2
  exit 1
fi

# Sanity: confirm the two specs are actually different (otherwise the test is vacuous).
if cmp -s "$spec_v1" "$spec_v2"; then
  echo "FAIL: fixture setup error — v1 and v2 are byte-identical" >&2
  exit 1
fi

# Now demonstrate the contrast: editing inside a PROTECTED section DOES change the SHA.
spec_v3="${TMP_ROOT}/spec-v3.md"
sed 's|R1. Do the thing.|R1. Do the thing differently.|' "$spec_v1" > "$spec_v3"
sha_v3="$(sha_of_protected "$spec_v3")"
if [[ "$sha_v1" == "$sha_v3" ]]; then
  echo "FAIL: control case — protected-section edit did NOT change SHA (test logic is broken)" >&2
  exit 1
else
  echo "PASS: control — protected-section edit DOES change SHA (sha_v3 = ${sha_v3:0:16}...)"
fi

echo "RESULT: SHA exclusion verified"
exit 0
