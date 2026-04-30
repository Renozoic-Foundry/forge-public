#!/usr/bin/env bash
# test-is-forge-command — regression test for is_forge_command (Spec 364)
#
# Defends against the SIGPIPE-under-pipefail false-CONFLICT class:
#   strip_frontmatter | head -5 | grep -q  →  exit 141 when grep matches early
#   and head closes stdin → strip_frontmatter SIGPIPEs → pipefail propagates 141.
#
# THE TEST MUST RUN UNDER `set -euo pipefail`. Without pipefail, the bug is invisible.
#
# Exits 0 on PASS, 1 on FAIL.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FORGE_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# shellcheck source=/dev/null
source "${FORGE_DIR}/lib/sync-helpers.sh"

PASS_COUNT=0
FAIL_COUNT=0

assert_true() {
  local description="$1"
  local file="$2"
  if is_forge_command "$file"; then
    echo "  PASS: $description"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    echo "  FAIL: $description (exit=$?)"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
}

assert_false() {
  local description="$1"
  local file="$2"
  if is_forge_command "$file"; then
    echo "  FAIL: $description (returned TRUE — should be FALSE)"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  else
    echo "  PASS: $description"
    PASS_COUNT=$((PASS_COUNT + 1))
  fi
}

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

# === Fixture A: close.md-style — frontmatter-less, body starts with # Framework: FORGE ===
# (The leading blank line on the real close.md is incidental; replicate it for fidelity.)
# Pad the body large enough that strip_frontmatter has not finished writing when head -5 closes
# its stdin — this is the condition that triggers SIGPIPE under pipefail in the buggy version.
# Default Linux pipe buffer is 64KiB; we generate ≥128KiB of body padding to force the upstream
# subshell into a blocking write that gets SIGPIPE'd when the downstream head -5 closes early.
{
  printf '\n'
  printf '# Framework: FORGE\n'
  printf '# Model-Tier: sonnet\n'
  printf '<!-- multi-block mode: serialized -->\n\n'
  for i in $(seq 1 2000); do
    printf 'Body padding line %d: needed to overflow the pipe buffer so strip_frontmatter blocks on write and SIGPIPEs when head -5 closes.\n' "$i"
  done
} > "${TMP_ROOT}/fixture-close-style.md"

# === Fixture B: implement.md-style — leading YAML frontmatter, then # Framework: FORGE ===
{
  printf -- '---\n'
  printf 'name: implement\n'
  printf 'description: "Build a spec end-to-end with evidence gates"\n'
  printf 'workflow_stage: implementation\n'
  printf -- '---\n\n'
  printf '# Framework: FORGE\n'
  printf '# Model-Tier: sonnet\n'
  printf '<!-- multi-block mode: serialized -->\n\n'
  for i in $(seq 1 2000); do
    printf 'Body padding line %d: needed to overflow the pipe buffer so strip_frontmatter blocks on write and SIGPIPEs when head -5 closes.\n' "$i"
  done
} > "${TMP_ROOT}/fixture-implement-style.md"

# === Fixture C: ## Subcommand variant ===
cat > "${TMP_ROOT}/fixture-subcommand-style.md" <<'EOF'
## Subcommand: foo

Body content here.
Padding line 2.
Padding line 3.
Padding line 4.
Padding line 5.
Padding line 6.
EOF

# === Fixture D: negative — a project-specific command without the FORGE marker ===
cat > "${TMP_ROOT}/fixture-project-specific.md" <<'EOF'
# My Project Custom Command

This is a project-specific command that should NOT be recognized as FORGE.
It should remain skipped under --force so it isn't overwritten.
Padding line 1.
Padding line 2.
Padding line 3.
Padding line 4.
Padding line 5.
EOF

# === Fixture E: negative — empty file ===
: > "${TMP_ROOT}/fixture-empty.md"

# === Fixture F: negative — frontmatter only, no body marker ===
cat > "${TMP_ROOT}/fixture-frontmatter-only.md" <<'EOF'
---
name: not-forge
description: "Project command, no FORGE marker"
---
# Some other heading
Body content without the FORGE marker.
Padding line 1.
Padding line 2.
EOF

echo "Test: is_forge_command under set -euo pipefail (defends against Spec 364 SIGPIPE class)"
echo ""
echo "Positive cases (must return TRUE):"
assert_true "fixture A: close.md-style (leading blank line + FORGE marker)" "${TMP_ROOT}/fixture-close-style.md"
assert_true "fixture B: implement.md-style (frontmatter then FORGE marker)" "${TMP_ROOT}/fixture-implement-style.md"
assert_true "fixture C: ## Subcommand: variant" "${TMP_ROOT}/fixture-subcommand-style.md"

# Real-world repository files — only run the assertion if the path exists (test may be run in
# isolated fixture environments without the project tree).
if [[ -f "${FORGE_DIR}/../.claude/commands/close.md" ]]; then
  assert_true "real .claude/commands/close.md (Spec 364 primary failure case)" "${FORGE_DIR}/../.claude/commands/close.md"
fi
if [[ -f "${FORGE_DIR}/../.claude/commands/implement.md" ]]; then
  assert_true "real .claude/commands/implement.md (Spec 364 primary failure case)" "${FORGE_DIR}/../.claude/commands/implement.md"
fi

echo ""
echo "Negative cases (must return FALSE):"
assert_false "fixture D: project-specific command (no FORGE marker)" "${TMP_ROOT}/fixture-project-specific.md"
assert_false "fixture E: empty file" "${TMP_ROOT}/fixture-empty.md"
assert_false "fixture F: frontmatter only, body without marker" "${TMP_ROOT}/fixture-frontmatter-only.md"
assert_false "missing file (does not exist)" "${TMP_ROOT}/does-not-exist.md"

echo ""
echo "=== Test Summary ==="
echo "  PASS: $PASS_COUNT"
echo "  FAIL: $FAIL_COUNT"

if [[ $FAIL_COUNT -gt 0 ]]; then
  exit 1
fi
exit 0
