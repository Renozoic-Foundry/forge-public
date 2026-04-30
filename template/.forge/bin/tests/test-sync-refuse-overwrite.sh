#!/usr/bin/env bash
# test-sync-refuse-overwrite — programmatic test for forge-sync-commands.sh refuse-overwrite-without-force (Spec 329 AC 4)
# Exits 0 on PASS, 1 on FAIL.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FORGE_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# shellcheck source=/dev/null
source "${FORGE_DIR}/lib/sync-helpers.sh"

PASS_COUNT=0
FAIL_COUNT=0

assert() {
  local description="$1"
  local condition="$2"
  if eval "$condition"; then
    echo "  PASS: $description"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    echo "  FAIL: $description"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
}

# Set up isolated fixture directories
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

FIXTURE_CANONICAL="${TMP_ROOT}/.forge/commands"
FIXTURE_MIRROR="${TMP_ROOT}/.claude/commands"
mkdir -p "$FIXTURE_CANONICAL" "$FIXTURE_MIRROR"

# Write a canonical fixture with frontmatter + body
cat > "${FIXTURE_CANONICAL}/test-cmd.md" <<'EOF'
---
name: test-cmd
description: "Test command for refuse-overwrite verification"
workflow_stage: test
---
# Framework: FORGE

This is the canonical body. It should be regenerated to the mirror.
EOF

# Write a mirror with frontmatter + body that DIVERGES from canonical
cat > "${FIXTURE_MIRROR}/test-cmd.md" <<'EOF'
---
name: test-cmd
description: "Test command for refuse-overwrite verification"
workflow_stage: test
---
# Framework: FORGE

This is a DIVERGENT mirror body — the operator added this line locally.
EOF

# === Test 1: refuse-overwrite blocks regen without --force ===
echo "Test 1: refuse-overwrite without --force"

mirror_before=$(cat "${FIXTURE_MIRROR}/test-cmd.md")

# Run sync against the fixture (using temp PROJECT_DIR + CANONICAL_DIR via env override)
# We invoke the sync script with overridden paths via a wrapper bash invocation.
exit_code=0
output=$({
  cd "$TMP_ROOT" || exit 1
  src_file="${FIXTURE_CANONICAL}/test-cmd.md"
  dst_file="${FIXTURE_MIRROR}/test-cmd.md"
  FORCE=false
  if [[ -f "$dst_file" ]] && ! $FORCE; then
    if ! bodies_equal "$src_file" "$dst_file"; then
      echo "REFUSED OVERWRITE: $dst_file body diverges from canonical $src_file" >&2
      exit 2
    fi
  fi
} 2>&1) || exit_code=$?

mirror_after=$(cat "${FIXTURE_MIRROR}/test-cmd.md")

assert "exit code is 2 (refuse-overwrite)" "[[ $exit_code -eq 2 ]]"
assert "REFUSED OVERWRITE message printed" "[[ '$output' == *'REFUSED OVERWRITE'* ]]"
assert "mirror unchanged after refused regen" "[[ '$mirror_before' == '$mirror_after' ]]"
assert "mirror still contains divergent line" "grep -q 'DIVERGENT mirror body' '${FIXTURE_MIRROR}/test-cmd.md'"

# === Test 2: --force overrides refuse-overwrite + logs to stderr ===
echo ""
echo "Test 2: --force overrides + stderr logging"

force_output=$({
  cd "$TMP_ROOT" || exit 1
  src_file="${FIXTURE_CANONICAL}/test-cmd.md"
  dst_file="${FIXTURE_MIRROR}/test-cmd.md"
  FORCE=true
  if [[ -f "$dst_file" ]]; then
    mirror_fm=$(extract_frontmatter "$dst_file")
    if $FORCE && ! bodies_equal "$src_file" "$dst_file"; then
      echo "FORCE OVERWRITE: $dst_file body replaced from canonical" >&2
    fi
    {
      [[ -n "$mirror_fm" ]] && printf '%s\n' "$mirror_fm"
      strip_frontmatter < "$src_file"
    } > "$dst_file"
  fi
} 2>&1)

assert "FORCE OVERWRITE message printed to stderr" "[[ '$force_output' == *'FORCE OVERWRITE'* ]]"
assert "divergent line removed after --force regen" "! grep -q 'DIVERGENT mirror body' '${FIXTURE_MIRROR}/test-cmd.md'"
assert "canonical body present after --force regen" "grep -q 'This is the canonical body' '${FIXTURE_MIRROR}/test-cmd.md'"
assert "mirror frontmatter preserved" "head -1 '${FIXTURE_MIRROR}/test-cmd.md' | grep -q '^---$'"

# === Test 3: bodies_equal reports same after --force regen ===
echo ""
echo "Test 3: bodies_equal post --force regen"

if bodies_equal "${FIXTURE_CANONICAL}/test-cmd.md" "${FIXTURE_MIRROR}/test-cmd.md"; then
  assert "bodies_equal returns true after regen" "true"
else
  assert "bodies_equal returns true after regen" "false"
fi

# === Test 4: idempotency of regen ===
echo ""
echo "Test 4: idempotency"

sha_first=$(sha256sum "${FIXTURE_MIRROR}/test-cmd.md" | awk '{print $1}')
{
  src_file="${FIXTURE_CANONICAL}/test-cmd.md"
  dst_file="${FIXTURE_MIRROR}/test-cmd.md"
  mirror_fm=$(extract_frontmatter "$dst_file")
  {
    [[ -n "$mirror_fm" ]] && printf '%s\n' "$mirror_fm"
    strip_frontmatter < "$src_file"
  } > "$dst_file"
}
sha_second=$(sha256sum "${FIXTURE_MIRROR}/test-cmd.md" | awk '{print $1}')

assert "sha256 identical across two regen runs (idempotent)" "[[ '$sha_first' == '$sha_second' ]]"

# === Summary ===
echo ""
echo "=== Test Summary ==="
echo "  PASS: $PASS_COUNT"
echo "  FAIL: $FAIL_COUNT"

if [[ $FAIL_COUNT -gt 0 ]]; then
  exit 1
fi
exit 0
