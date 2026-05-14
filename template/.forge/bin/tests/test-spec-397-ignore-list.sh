#!/usr/bin/env bash
# Spec 397 — safety-config audit ignore-list fixture.
#
# Covers AC4:
#   AC4a: A token in the ignore-list is suppressed from list (ii) (NOT in MISSING output).
#   AC4b: The same token appears in list (iii) with the reason text from the yaml.
#   AC4c: --check-only mode emits NO output for the ignored token (no MISSING line).
#
# Strategy: run the actual audit script against a synthetic registry that points to a
# synthetic config file containing one ignored token + one not-ignored token. This
# treats the real audit + real ignore-list helper as the load-bearing surface and
# avoids fixture/mock divergence per the spec's Risks section.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
AUDIT="$REPO_ROOT/scripts/safety-backfill-audit.sh"

if [[ ! -f "$AUDIT" ]]; then
  echo "FAIL — safety-backfill-audit.sh not found at $AUDIT" >&2
  exit 1
fi

TMP_REPO="$(mktemp -d -t forge-spec-397-XXXXXX)"
trap 'rm -rf "$TMP_REPO"' EXIT

PASS=0
FAIL=0

mark_pass() { echo "  PASS — $1"; PASS=$((PASS+1)); }
mark_fail() { echo "  FAIL — $1"; FAIL=$((FAIL+1)); }

# Build a minimal forge-like sandbox in $TMP_REPO. The audit script resolves its
# REPO_ROOT relative to its own location, so we copy the audit + helper there.
mkdir -p "$TMP_REPO/scripts"
mkdir -p "$TMP_REPO/.forge/lib"
mkdir -p "$TMP_REPO/.forge/state"
mkdir -p "$TMP_REPO/docs/specs"
cp "$AUDIT" "$TMP_REPO/scripts/safety-backfill-audit.sh"
chmod +x "$TMP_REPO/scripts/safety-backfill-audit.sh"
cp "$REPO_ROOT/.forge/lib/safety-config.sh" "$TMP_REPO/.forge/lib/safety-config.sh"

# Synthetic config file with two safety-prefix tokens.
SYNTH_CFG="$TMP_REPO/test-config.yaml"
cat > "$SYNTH_CFG" <<'EOF'
# Synthetic config for Spec 397 fixture
require_fixture_token: true
guard_real_safety: true
EOF

# Registry that points only at our synthetic config file.
cat > "$TMP_REPO/.forge/safety-config-paths.yaml" <<'EOF'
patterns:
  - test-config.yaml
EOF

# Ignore-list with require_fixture_token in it; guard_real_safety is NOT ignored.
cat > "$TMP_REPO/.forge/safety-config-ignore.yaml" <<'EOF'
version: 1
ignore:
  - token: require_fixture_token
    reason: "Spec 397 fixture token — not a real safety property."
    added: 2026-05-08
    spec: 397
EOF

cd "$TMP_REPO"

# --- AC4a + AC4b: dry-run output ---
DRY_OUT="$(bash scripts/safety-backfill-audit.sh --dry-run 2>&1 || true)"

if echo "$DRY_OUT" | grep -qE '^MISSING:.*require_fixture_token'; then
  mark_fail "AC4a — require_fixture_token must NOT appear in list (ii) MISSING"
else
  mark_pass "AC4a — require_fixture_token suppressed from list (ii)"
fi

if echo "$DRY_OUT" | grep -qE '^IGNORED:.*require_fixture_token.*Spec 397 fixture token'; then
  mark_pass "AC4b — require_fixture_token in list (iii) with reason text"
else
  mark_fail "AC4b — require_fixture_token must appear in list (iii) with reason"
  echo "$DRY_OUT" | sed 's/^/    /'
fi

# Sanity check: the non-ignored token IS classified as MISSING.
if echo "$DRY_OUT" | grep -qE '^MISSING:.*guard_real_safety'; then
  mark_pass "control — non-ignored token still appears in (ii) MISSING"
else
  mark_fail "control — guard_real_safety should appear in (ii) MISSING"
fi

# --- AC4c: --check-only must be silent for ignored tokens ---
# Even when the deadline has "passed" (we don't write a deadline marker in this
# fixture, but the relevant assertion is that the ignored token never appears).
CHK_OUT="$(bash scripts/safety-backfill-audit.sh --check-only 2>&1 || true)"

if echo "$CHK_OUT" | grep -qE 'require_fixture_token'; then
  mark_fail "AC4c — --check-only must NOT mention require_fixture_token"
  echo "$CHK_OUT" | sed 's/^/    /'
else
  mark_pass "AC4c — --check-only silent on ignored token"
fi

# Sanity: --check-only DOES emit MISSING for the non-ignored token.
if echo "$CHK_OUT" | grep -qE '^MISSING:.*guard_real_safety'; then
  mark_pass "control — --check-only emits MISSING for guard_real_safety"
else
  mark_fail "control — --check-only should emit MISSING for guard_real_safety"
fi

echo ""
echo "Spec 397 fixture: $PASS pass / $FAIL fail"
[[ "$FAIL" -eq 0 ]] || exit 1
exit 0
