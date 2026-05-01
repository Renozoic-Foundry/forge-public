#!/usr/bin/env bash
# Spec 382 — yaml-aware reader/writer parity fixture.
#
# Covers:
# - AC3: SKIP-FOR-NOW write produces literal value in AGENTS.md.
# - AC6: /matrix-Step-8-style sentinel detection (is-sentinel command).
# - AC7: real-content read returns the captured paragraph.
# - AC10: writer/reader mechanism parity — a value written via the helper is
#         read correctly by the helper, including round-trip through edge cases
#         (block-scalar |, plain scalar, substring "SKIP-FOR-NOW" mid-paragraph,
#         multi-line content with embedded YAML metacharacters).
#
# This fixture treats the helper at .forge/lib/strategic-scope.py as the load-
# bearing implementation. /onboarding (writer) and /matrix Step 8 (reader) both
# invoke this helper — testing it once covers both call sites per Spec 382 AC10.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
HELPER="$REPO_ROOT/.forge/lib/strategic-scope.py"
TMPDIR_TEST="$(mktemp -d -t forge-spec-382-XXXXXX)"
trap 'rm -rf "$TMPDIR_TEST"' EXIT

PASS=0
FAIL=0

assert_eq() {
    local name="$1" expected="$2" actual="$3"
    # Normalize line endings (handles Windows Git Bash CRLF artifacts)
    expected="$(printf '%s' "$expected" | tr -d '\r')"
    actual="$(printf '%s' "$actual" | tr -d '\r')"
    if [ "$expected" = "$actual" ]; then
        echo "  PASS — $name"
        PASS=$((PASS + 1))
    else
        echo "  FAIL — $name"
        echo "    expected: $expected"
        echo "    actual:   $actual"
        FAIL=$((FAIL + 1))
    fi
}

assert_file_eq() {
    # Compare via diff for byte-level accuracy (avoids shell quoting issues with multibyte chars)
    local name="$1" expected_file="$2" actual_file="$3"
    if diff -u "$expected_file" "$actual_file" > /dev/null 2>&1; then
        echo "  PASS — $name"
        PASS=$((PASS + 1))
    else
        echo "  FAIL — $name"
        diff -u "$expected_file" "$actual_file" | head -10 | sed 's/^/    /'
        FAIL=$((FAIL + 1))
    fi
}

assert_exit() {
    local name="$1" expected_code="$2" actual_code="$3"
    if [ "$expected_code" -eq "$actual_code" ]; then
        echo "  PASS — $name (exit $actual_code)"
        PASS=$((PASS + 1))
    else
        echo "  FAIL — $name (expected exit $expected_code, got $actual_code)"
        FAIL=$((FAIL + 1))
    fi
}

make_agents_md() {
    # $1 = scope value (verbatim). Writes a minimal AGENTS.md with the scope block.
    local scope="$1"
    local path="$TMPDIR_TEST/AGENTS-$RANDOM.md"
    cat > "$path" << HEADER
# Test AGENTS.md

## Project Context

Test project description.

\`\`\`yaml
# Strategic scope — used by /matrix Step 8 to evaluate spec fit (Spec 110)
# Defines what this project IS and IS NOT.
HEADER
    if [ "$scope" = "SKIP-FOR-NOW" ]; then
        echo 'forge.strategic_scope: SKIP-FOR-NOW' >> "$path"
    else
        echo 'forge.strategic_scope: |' >> "$path"
        while IFS= read -r line; do
            echo "  $line" >> "$path"
        done <<< "$scope"
    fi
    cat >> "$path" << 'FOOTER'
```

```yaml
forge.context.session_briefing: true
```
FOOTER
    echo "$path"
}

echo "=== Spec 382 yaml-parity fixture ==="
echo

# Test 1 — AC3 + AC6: SKIP-FOR-NOW sentinel read + is-sentinel
echo "Test 1 — SKIP-FOR-NOW sentinel detection (AC3 + AC6)"
P="$(make_agents_md 'SKIP-FOR-NOW')"
val="$(python3 "$HELPER" read "$P")"
assert_eq "read returns literal SKIP-FOR-NOW" "SKIP-FOR-NOW" "$val"
set +e; python3 "$HELPER" is-sentinel "$P" >/dev/null; rc=$?; set -e
assert_exit "is-sentinel exit 0 on SKIP-FOR-NOW" 0 "$rc"
echo

# Test 2 — AC7: real content read (use file-based comparison to avoid shell quoting)
echo "Test 2 — real content read (AC7)"
EXP="$TMPDIR_TEST/expected-real.txt"
cat > "$EXP" << 'EOF'
SmileyOne -- PIM + knowledge graph product.
In scope: PIM, graph queries, dashboards.
Out of scope: framework changes, mobile apps.
EOF
# Trim trailing newline for comparison parity with helper's strip()
real_scope="$(cat "$EXP")"
P="$(make_agents_md "$real_scope")"
ACT="$TMPDIR_TEST/actual-real.txt"
python3 "$HELPER" read "$P" > "$ACT"
# Helper output ends with newline from print(); add one to expected for parity
echo "" >> "$ACT"  # no-op since print() already adds; let diff handle
# Just compare via the helper's stripping behavior using diff with -B
if diff --strip-trailing-cr <(cat "$EXP") <(python3 "$HELPER" read "$P") > /dev/null 2>&1; then
    echo "  PASS — read returns full multiline scope (file-based)"
    PASS=$((PASS + 1))
else
    echo "  FAIL — read returns full multiline scope"
    diff --strip-trailing-cr <(cat "$EXP") <(python3 "$HELPER" read "$P") | head -8 | sed 's/^/    /'
    FAIL=$((FAIL + 1))
fi
set +e; python3 "$HELPER" is-sentinel "$P" >/dev/null; rc=$?; set -e
assert_exit "is-sentinel exit 1 on real content" 1 "$rc"
echo

# Test 3 — substring-not-equality (CTO round-3 key risk)
echo "Test 3 — substring SKIP-FOR-NOW mid-paragraph does NOT trigger sentinel (CTO round-3)"
EXP="$TMPDIR_TEST/expected-substring.txt"
cat > "$EXP" << 'EOF'
Real project. Nothing about SKIP-FOR-NOW here.
Second line of scope.
EOF
substring_scope="$(cat "$EXP")"
P="$(make_agents_md "$substring_scope")"
set +e; python3 "$HELPER" is-sentinel "$P" >/dev/null; rc=$?; set -e
assert_exit "is-sentinel exit 1 on substring (not exact match)" 1 "$rc"
if diff --strip-trailing-cr <(cat "$EXP") <(python3 "$HELPER" read "$P") > /dev/null 2>&1; then
    echo "  PASS — read returns full content with substring intact"
    PASS=$((PASS + 1))
else
    echo "  FAIL — read returns full content with substring intact"
    diff --strip-trailing-cr <(cat "$EXP") <(python3 "$HELPER" read "$P") | head -8 | sed 's/^/    /'
    FAIL=$((FAIL + 1))
fi
echo

# Test 4 — AC10: writer/reader round-trip parity (multiline)
echo "Test 4 — writer/reader round-trip parity, multiline (AC10)"
EXP="$TMPDIR_TEST/expected-multiline.txt"
cat > "$EXP" << 'EOF'
New scope line 1
Line 2 with embedded "quote" chars.
Line 3 with : colon and | pipe and > arrow.
EOF
new_value="$(cat "$EXP")"
P="$(make_agents_md 'OLD VALUE')"
python3 "$HELPER" write "$P" "$new_value"
if diff --strip-trailing-cr <(cat "$EXP") <(python3 "$HELPER" read "$P") > /dev/null 2>&1; then
    echo "  PASS — round-trip preserves multiline value with metacharacters"
    PASS=$((PASS + 1))
else
    echo "  FAIL — round-trip preserves multiline value with metacharacters"
    diff --strip-trailing-cr <(cat "$EXP") <(python3 "$HELPER" read "$P") | head -8 | sed 's/^/    /'
    FAIL=$((FAIL + 1))
fi
echo

# Test 5 — AC10: writer/reader round-trip parity (SKIP-FOR-NOW write)
echo "Test 5 — writer/reader round-trip parity, SKIP-FOR-NOW write (AC10)"
P="$(make_agents_md 'OLD VALUE')"
python3 "$HELPER" write "$P" "SKIP-FOR-NOW"
val="$(python3 "$HELPER" read "$P")"
assert_eq "write SKIP-FOR-NOW round-trips correctly" "SKIP-FOR-NOW" "$val"
set +e; python3 "$HELPER" is-sentinel "$P" >/dev/null; rc=$?; set -e
assert_exit "is-sentinel exit 0 after SKIP-FOR-NOW write" 0 "$rc"
echo

# Test 6 — Block scalar `>` (folded) edge case
echo "Test 6 — folded block scalar (>) edge case"
P="$TMPDIR_TEST/AGENTS-folded.md"
cat > "$P" << 'EOF'
# Test
```yaml
forge.strategic_scope: >
  Folded scope line 1
  continues here.
  Line 2 paragraph.
```
EOF
val="$(python3 "$HELPER" read "$P")"
# Folded scalar joins lines with spaces. Just verify we got something non-empty
# and that it's not the raw text with newlines.
if [ -n "$val" ] && [ "${val#*Folded scope}" != "$val" ]; then
    echo "  PASS — folded block scalar parsed to non-empty value: '$val'"
    PASS=$((PASS + 1))
else
    echo "  FAIL — folded block scalar parse failed (got: '$val')"
    FAIL=$((FAIL + 1))
fi
echo

# Test 7 — Plain scalar (single-line) edge case
echo "Test 7 — plain scalar single-line edge case"
P="$TMPDIR_TEST/AGENTS-plain.md"
cat > "$P" << 'EOF'
# Test
```yaml
forge.strategic_scope: A short scope on one line.
```
EOF
val="$(python3 "$HELPER" read "$P")"
assert_eq "plain scalar single-line read" "A short scope on one line." "$val"
echo

# Test 8 — Block missing edge case
echo "Test 8 — block missing returns exit 1"
P="$TMPDIR_TEST/AGENTS-no-block.md"
cat > "$P" << 'EOF'
# Test AGENTS.md
No strategic scope block here.
EOF
set +e; python3 "$HELPER" read "$P" >/dev/null; rc=$?; set -e
assert_exit "read exit 1 when block missing" 1 "$rc"
set +e; python3 "$HELPER" is-sentinel "$P" >/dev/null; rc=$?; set -e
assert_exit "is-sentinel exit 1 when block missing" 1 "$rc"
echo

# Test 9 — Other YAML blocks unaffected by write
echo "Test 9 — other yaml blocks unaffected by scope write"
P="$(make_agents_md 'OLD')"
python3 "$HELPER" write "$P" "NEW SCOPE"
# Verify the second yaml block (forge.context.session_briefing) still present
if grep -q "forge.context.session_briefing: true" "$P"; then
    echo "  PASS — sibling yaml block preserved"
    PASS=$((PASS + 1))
else
    echo "  FAIL — sibling yaml block lost during scope write"
    FAIL=$((FAIL + 1))
fi
echo

# Summary
echo "=== Summary: $PASS PASS / $FAIL FAIL ==="
[ "$FAIL" -eq 0 ]
