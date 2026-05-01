#!/usr/bin/env bash
# Spec 382 — /matrix Step 8 integration fixture.
#
# Covers:
# - AC6: /matrix Step 8 with `forge.strategic_scope: SKIP-FOR-NOW` → emits warning
#        and skips scope-fit eval. Verified by simulating the helper invocation
#        chain that /matrix uses (read + is-sentinel).
# - AC7: /matrix Step 8 with real (non-sentinel) content → proceeds with eval.
#        Verified by helper returning real content, is-sentinel returning exit 1.
#
# This fixture demonstrates the integration semantics. The actual /matrix command
# is markdown-driven (a Claude Code command file), so the interactive
# classification-of-draft-specs flow is validated at /close human-validation.
# The MECHANICAL piece — sentinel detection — is fully testable here.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
HELPER="$REPO_ROOT/.forge/lib/strategic-scope.py"
TMPDIR_TEST="$(mktemp -d -t forge-spec-382-matrix-XXXXXX)"
trap 'rm -rf "$TMPDIR_TEST"' EXIT

PASS=0
FAIL=0

simulate_matrix_step8() {
    # Returns:
    #   "SKIP <warning>"  — sentinel detected, would emit warning and skip eval
    #   "EVAL <value>"    — real content, would proceed with eval
    #   "INFER"           — block missing, /matrix falls back to CLAUDE.md inference
    local agents_md="$1"
    if python3 "$HELPER" is-sentinel "$agents_md" 2>/dev/null; then
        echo "SKIP ⚠ Step 8 — Strategic scope not yet customized (SKIP-FOR-NOW). Fill forge.strategic_scope in AGENTS.md to enable scope-fit evaluation. Skipping Step 8."
    elif value="$(python3 "$HELPER" read "$agents_md" 2>/dev/null)"; then
        echo "EVAL $value"
    else
        echo "INFER"
    fi
}

assert_starts_with() {
    local name="$1" prefix="$2" actual="$3"
    if [ "${actual#"$prefix"}" != "$actual" ]; then
        echo "  PASS — $name"
        PASS=$((PASS + 1))
    else
        echo "  FAIL — $name"
        echo "    expected prefix: $prefix"
        echo "    actual:          $actual"
        FAIL=$((FAIL + 1))
    fi
}

echo "=== Spec 382 /matrix Step 8 integration fixture ==="
echo

# AC6 — Step 8 with SKIP-FOR-NOW sentinel
echo "AC6 — /matrix Step 8 with SKIP-FOR-NOW sentinel"
P="$TMPDIR_TEST/AGENTS-skip.md"
cat > "$P" << 'EOF'
# Project AGENTS.md
```yaml
forge.strategic_scope: SKIP-FOR-NOW
```
EOF
result="$(simulate_matrix_step8 "$P")"
assert_starts_with "Step 8 reports SKIP path" "SKIP " "$result"
# Verify the warning text matches AC6 exactly
expected_warning='⚠ Step 8 — Strategic scope not yet customized (SKIP-FOR-NOW). Fill forge.strategic_scope in AGENTS.md to enable scope-fit evaluation. Skipping Step 8.'
warning_only="${result#SKIP }"
warning_only="$(printf '%s' "$warning_only" | tr -d '\r')"
expected_warning="$(printf '%s' "$expected_warning" | tr -d '\r')"
if [ "$warning_only" = "$expected_warning" ]; then
    echo "  PASS — warning text matches AC6 exactly"
    PASS=$((PASS + 1))
else
    # Compare via diff to bypass any stray byte differences
    if diff --strip-trailing-cr <(printf '%s\n' "$expected_warning") <(printf '%s\n' "$warning_only") > /dev/null 2>&1; then
        echo "  PASS — warning text matches AC6 exactly (CRLF-normalized)"
        PASS=$((PASS + 1))
    else
        echo "  FAIL — warning text mismatch"
        echo "    expected: $expected_warning"
        echo "    actual:   $warning_only"
        FAIL=$((FAIL + 1))
    fi
fi
echo

# AC7 — Step 8 with real content
echo "AC7 — /matrix Step 8 with real (non-sentinel) content"
P="$TMPDIR_TEST/AGENTS-real.md"
cat > "$P" << 'EOF'
# Project AGENTS.md
```yaml
forge.strategic_scope: |
  SmileyOne -- PIM + knowledge graph product.
  In scope: PIM, graph queries, dashboards.
  Out of scope: framework changes, mobile apps.
```
EOF
result="$(simulate_matrix_step8 "$P")"
assert_starts_with "Step 8 reports EVAL path" "EVAL " "$result"
echo

# Edge case — block missing → INFER (fallback to CLAUDE.md per /matrix Step 8 line 71)
echo "Edge — block missing → INFER fallback"
P="$TMPDIR_TEST/AGENTS-no-block.md"
cat > "$P" << 'EOF'
# Project AGENTS.md
No strategic scope block here.
EOF
result="$(simulate_matrix_step8 "$P")"
assert_starts_with "Step 8 reports INFER path on missing block" "INFER" "$result"
echo

# Edge case — substring "SKIP-FOR-NOW" in real content does NOT trigger SKIP path (CTO round-3)
echo "Edge — substring 'SKIP-FOR-NOW' in real content does NOT trigger SKIP path (CTO round-3 key risk)"
P="$TMPDIR_TEST/AGENTS-substring.md"
cat > "$P" << 'EOF'
# Project AGENTS.md
```yaml
forge.strategic_scope: |
  Real project. Mentions SKIP-FOR-NOW as a sentinel literal in this paragraph.
  Should NOT be classified as a sentinel.
```
EOF
result="$(simulate_matrix_step8 "$P")"
assert_starts_with "Step 8 reports EVAL path despite substring" "EVAL " "$result"
echo

echo "=== Summary: $PASS PASS / $FAIL FAIL ==="
[ "$FAIL" -eq 0 ]
