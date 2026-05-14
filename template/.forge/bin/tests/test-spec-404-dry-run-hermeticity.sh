#!/usr/bin/env bash
# test-spec-404-dry-run-hermeticity.sh
#
# Tests for the assert-hermetic-dry-run helper introduced by Spec 404.
# Verifies both the positive path (hermetic command leaves dir unchanged)
# and the negative path (mutating command is detected).

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HELPER="$SCRIPT_DIR/lib/assert-hermetic-dry-run.sh"

if [ ! -f "$HELPER" ]; then
    echo "FAIL: helper not found at $HELPER" >&2
    exit 1
fi

# shellcheck source=lib/assert-hermetic-dry-run.sh
source "$HELPER"

PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); printf '  PASS: %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); printf '  FAIL: %s\n' "$1" >&2; }

cleanup_dir() {
    [ -n "${1:-}" ] && [ -d "$1" ] && rm -rf "$1"
}

# ---------- Test 1: empty dir, no-op command -> hermetic ----------
echo "Test 1: no-op against empty dir"
TMP=$(mktemp -d)
trap 'cleanup_dir "$TMP"' EXIT
if assert_hermetic_dry_run "$TMP" -- true; then
    pass "no-op hermetic"
else
    fail "no-op flagged as non-hermetic"
fi
cleanup_dir "$TMP"

# ---------- Test 2: empty dir, mutating command -> non-hermetic ----------
echo "Test 2: mutating command against empty dir"
TMP=$(mktemp -d)
if assert_hermetic_dry_run "$TMP" -- bash -c "touch '$TMP/leak'" 2>/dev/null; then
    fail "mutation NOT detected (vacuous helper)"
else
    pass "mutation detected"
fi
cleanup_dir "$TMP"

# ---------- Test 3: non-empty dir, no-op -> hermetic ----------
echo "Test 3: no-op against pre-populated dir"
TMP=$(mktemp -d)
echo "alpha" > "$TMP/a.txt"
mkdir -p "$TMP/sub"
echo "beta" > "$TMP/sub/b.txt"
if assert_hermetic_dry_run "$TMP" -- bash -c "echo 'reading...' >/dev/null"; then
    pass "no-op hermetic on populated dir"
else
    fail "no-op flagged on populated dir"
fi
cleanup_dir "$TMP"

# ---------- Test 4: non-empty dir, content mutation -> detected ----------
echo "Test 4: content mutation against pre-populated dir"
TMP=$(mktemp -d)
echo "alpha" > "$TMP/a.txt"
if assert_hermetic_dry_run "$TMP" -- bash -c "echo 'altered' > '$TMP/a.txt'" 2>/dev/null; then
    fail "content mutation NOT detected"
else
    pass "content mutation detected"
fi
cleanup_dir "$TMP"

# ---------- Test 5: malformed invocation -> rc 2 ----------
echo "Test 5: malformed invocation (missing --)"
TMP=$(mktemp -d)
if assert_hermetic_dry_run "$TMP" true 2>/dev/null; then
    fail "malformed invocation returned 0"
else
    rc=$?
    if [ "$rc" = "2" ]; then
        pass "malformed invocation returned 2"
    else
        fail "malformed invocation returned $rc (expected 2)"
    fi
fi
cleanup_dir "$TMP"

# ---------- Test 6: nonexistent dir -> rc 2 ----------
echo "Test 6: nonexistent staging dir"
if assert_hermetic_dry_run "/this/does/not/exist-spec-404" -- true 2>/dev/null; then
    fail "nonexistent dir returned 0"
else
    rc=$?
    if [ "$rc" = "2" ]; then
        pass "nonexistent dir returned 2"
    else
        fail "nonexistent dir returned $rc (expected 2)"
    fi
fi

# ---------- Test 7: mtime-only change -> still hermetic ----------
echo "Test 7: mtime-only change does NOT trip helper"
TMP=$(mktemp -d)
echo "stable" > "$TMP/a.txt"
if assert_hermetic_dry_run "$TMP" -- bash -c "touch '$TMP/a.txt'"; then
    pass "mtime-only change is hermetic (correctly)"
else
    fail "mtime-only change incorrectly flagged"
fi
cleanup_dir "$TMP"

echo
echo "Spec 404 helper tests: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
