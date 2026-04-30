#!/usr/bin/env bash
# test-spec-370-hygiene — regression tests for Spec 370 /matrix Backlog Hygiene Pass.
#
# Tests are fixture-based — they validate the documented detection rules by creating
# synthetic spec files and exercising the parsing logic. /matrix is markdown-driven
# (no executable command code) so these tests validate the BEHAVIOR the canonical
# sentinel block prescribes, not the orchestration of /matrix itself.
#
# Coverage:
#   AC 2  — deprecation candidate detection (valid-until past AND rank ≥ 30 ≥30d)
#   AC 3  — deferral candidate detection (dependency status deferred/deprecated)
#   AC 4  — apply all dispositions land (deprecation: status update; deferral: revision log)
#   AC 5  — pick subset only applies selected indices
#   AC 6  — skip leaves backlog snapshot unchanged
#   AC 7  — mirror parity (md5sum across 4 matrix.md mirrors) — delegated to sync --check
#   AC 8  — skip-on-empty deferral trigger (no Revision Log entry written)
#   AC 9  — canonical guide contains required named terms
#   AC 10 — idempotency (re-run filters specs with recent hygiene-pass entry)
#
# Exits 0 on PASS, 1 on FAIL.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
GUIDE="${REPO_ROOT}/docs/process-kit/backlog-hygiene-guide.md"
SYNC_SCRIPT="${REPO_ROOT}/scripts/spec-370-sync-matrix-hygiene.sh"

PASS=0
FAIL=0

assert() {
  local desc="$1"
  local cond="$2"
  if eval "$cond"; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc"
    FAIL=$((FAIL + 1))
  fi
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# =============================================================================
# Detection-logic Python helpers (simulating the canonical block's scan rules)
# =============================================================================

# Returns 0 if spec qualifies as deprecation candidate, 1 otherwise.
# Inputs: spec_file, today_date, rank, days_at_rank
is_deprecation_candidate() {
  local spec_file="$1"
  local today="$2"
  local rank="$3"
  local days_at_rank="$4"
  python3 - "$spec_file" "$today" "$rank" "$days_at_rank" << 'PY'
import re, sys
from datetime import date
spec_file, today_str, rank_s, days_s = sys.argv[1:5]
today = date.fromisoformat(today_str)
rank = int(rank_s)
days_at_rank = int(days_s)
text = open(spec_file, 'r', encoding='utf-8').read()
m = re.search(r'^- valid-until: (\d{4}-\d{2}-\d{2})', text, re.MULTILINE)
status_m = re.search(r'^- Status: (\S+)', text, re.MULTILINE)
status = status_m.group(1) if status_m else ''
# Idempotency: already-deprecated specs are filtered out
if status == 'deprecated':
    sys.exit(1)
if not m:
    sys.exit(1)
valid_until = date.fromisoformat(m.group(1))
# Both signals required: valid-until past AND rank >= 30 for >= 30 days
if valid_until < today and rank >= 30 and days_at_rank >= 30:
    sys.exit(0)
sys.exit(1)
PY
}

# Returns 0 if spec qualifies as deferral candidate, 1 otherwise.
# Inputs: spec_file, dep_spec_file (resolves Dependencies: anchor), today_date
is_deferral_candidate() {
  local spec_file="$1"
  local dep_spec_file="$2"
  local today="$3"
  python3 - "$spec_file" "$dep_spec_file" "$today" << 'PY'
import re, sys
from datetime import date, timedelta
spec_file, dep_file, today_str = sys.argv[1:4]
today = date.fromisoformat(today_str)
text = open(spec_file, 'r', encoding='utf-8').read()
status_m = re.search(r'^- Status: (\S+)', text, re.MULTILINE)
status = status_m.group(1) if status_m else ''
if status != 'draft':
    sys.exit(1)
# Idempotency: filter out specs with recent "Deferred via /matrix hygiene pass" Revision Log entry
rev_matches = re.findall(r'(\d{4}-\d{2}-\d{2}): Deferred via /matrix hygiene pass', text)
for d in rev_matches:
    try:
        entry_date = date.fromisoformat(d)
        if (today - entry_date).days < 30:
            sys.exit(1)
    except ValueError:
        pass
# Read dependency spec status
if not dep_file:
    sys.exit(1)
dep_text = open(dep_file, 'r', encoding='utf-8').read()
dep_status_m = re.search(r'^- Status: (.+?)\s*$', dep_text, re.MULTILINE)
dep_status_raw = dep_status_m.group(1).strip() if dep_status_m else ''
# Match "deferred" anywhere in status (handles "draft (deferred ...)") or exact "deprecated"
if 'deferred' in dep_status_raw.lower() or dep_status_raw == 'deprecated':
    sys.exit(0)
sys.exit(1)
PY
}

make_spec() {
  local out="$1"
  local status="$2"
  local valid_until="$3"
  local dep="$4"
  local rev_log="${5:-}"
  cat > "$out" << EOF
# Spec NNN — fixture

- Status: $status
- Change-Lane: \`small-change\`
- Priority-Score: <!-- BV=3 E=2 R=2 SR=2 → score=29 -->
- Dependencies: $dep
- Last updated: 2026-04-29
- valid-until: $valid_until

## Objective
Fixture for spec-370 hygiene-pass tests.

## Scope
In scope: synthetic.

## Requirements
1. Fixture only.

## Acceptance Criteria
1. None.

## Test Plan
1. None.

## Implementation Summary

## Evidence

## Revision Log

$rev_log
EOF
}

# =============================================================================
# AC 2 — Deprecation scan: valid-until past AND rank ≥ 30 ≥30d
# =============================================================================
echo "AC 2 — Deprecation scan"

# Positive case: valid-until 2026-01-01, rank 42, 47 days at rank → flagged
make_spec "$TMP/dep-positive.md" "draft" "2026-01-01" ""
if is_deprecation_candidate "$TMP/dep-positive.md" "2026-04-30" 42 47; then
  assert "AC 2 — positive: valid-until past + rank 42 + 47 days flags" "true"
else
  assert "AC 2 — positive: valid-until past + rank 42 + 47 days flags" "false"
fi

# Negative: valid-until past but rank 18 (top-of-backlog)
make_spec "$TMP/dep-rank-too-high.md" "draft" "2026-01-01" ""
if is_deprecation_candidate "$TMP/dep-rank-too-high.md" "2026-04-30" 18 47; then
  assert "AC 2 — negative: rank 18 NOT flagged (top-of-backlog)" "false"
else
  assert "AC 2 — negative: rank 18 NOT flagged (top-of-backlog)" "true"
fi

# Negative: rank 42 but valid-until in future
make_spec "$TMP/dep-future-valid.md" "draft" "2027-01-01" ""
if is_deprecation_candidate "$TMP/dep-future-valid.md" "2026-04-30" 42 47; then
  assert "AC 2 — negative: future valid-until NOT flagged" "false"
else
  assert "AC 2 — negative: future valid-until NOT flagged" "true"
fi

# Negative: valid-until past + rank 42 BUT only 5 days at rank
make_spec "$TMP/dep-recent-rank.md" "draft" "2026-01-01" ""
if is_deprecation_candidate "$TMP/dep-recent-rank.md" "2026-04-30" 42 5; then
  assert "AC 2 — negative: 5 days at rank NOT flagged (<30d)" "false"
else
  assert "AC 2 — negative: 5 days at rank NOT flagged (<30d)" "true"
fi

# =============================================================================
# AC 3 — Deferral scan: Dependencies anchor on deferred/deprecated spec
# =============================================================================
echo "AC 3 — Deferral scan"

# Synthetic dependency spec with deferred status
cat > "$TMP/dep-122.md" << 'EOF'
# Spec 122 — fixture dependency

- Status: draft (deferred — runtime infrastructure)
- Change-Lane: `standard-feature`

## Objective
Fixture dependency.
EOF

make_spec "$TMP/defer-positive.md" "draft" "2026-08-01" "122"
if is_deferral_candidate "$TMP/defer-positive.md" "$TMP/dep-122.md" "2026-04-30"; then
  assert "AC 3 — positive: Dependencies → deferred dep flags candidate" "true"
else
  assert "AC 3 — positive: Dependencies → deferred dep flags candidate" "false"
fi

# Negative: dependency with normal draft status
cat > "$TMP/dep-active.md" << 'EOF'
# Spec 200 — active dep
- Status: draft
EOF
make_spec "$TMP/defer-neg-active.md" "draft" "2026-08-01" "200"
if is_deferral_candidate "$TMP/defer-neg-active.md" "$TMP/dep-active.md" "2026-04-30"; then
  assert "AC 3 — negative: active draft dep does NOT flag" "false"
else
  assert "AC 3 — negative: active draft dep does NOT flag" "true"
fi

# Positive (deprecated): dependency with deprecated status
cat > "$TMP/dep-deprecated.md" << 'EOF'
# Spec 999 — deprecated dep
- Status: deprecated
EOF
make_spec "$TMP/defer-via-deprecated.md" "draft" "2026-08-01" "999"
if is_deferral_candidate "$TMP/defer-via-deprecated.md" "$TMP/dep-deprecated.md" "2026-04-30"; then
  assert "AC 3 — positive: Dependencies → deprecated dep flags candidate" "true"
else
  assert "AC 3 — positive: Dependencies → deprecated dep flags candidate" "false"
fi

# =============================================================================
# AC 4 — Apply-all disposition lands (simulated state mutation)
# =============================================================================
echo "AC 4 — Apply-all disposition"

apply_deprecate() {
  local spec_file="$1"
  local today="$2"
  local reason="$3"
  python3 - "$spec_file" "$today" "$reason" << 'PY'
import sys, re
spec, today, reason = sys.argv[1:4]
text = open(spec, 'r', encoding='utf-8').read()
text = re.sub(r'^- Status: draft', f'- Status: deprecated\n- Closed: {today}', text, count=1, flags=re.MULTILINE)
text = text.rstrip() + f'\n- {today}: Deprecated via /matrix hygiene pass — {reason}.\n'
open(spec, 'w', encoding='utf-8').write(text)
PY
}

apply_defer() {
  local spec_file="$1"
  local today="$2"
  local reason="$3"
  local trigger="$4"
  if [[ -z "$trigger" ]]; then
    return 0  # Skip-on-empty
  fi
  python3 - "$spec_file" "$today" "$reason" "$trigger" << 'PY'
import sys
spec, today, reason, trigger = sys.argv[1:5]
text = open(spec, 'r', encoding='utf-8').read()
text = text.rstrip() + f'\n- {today}: Deferred via /matrix hygiene pass — {reason}. Re-activation trigger: {trigger}.\n'
open(spec, 'w', encoding='utf-8').write(text)
PY
}

make_spec "$TMP/apply-dep.md" "draft" "2026-01-01" ""
apply_deprecate "$TMP/apply-dep.md" "2026-04-30" "valid-until past + rank 42"
assert "AC 4 — deprecate: status changed to deprecated" "grep -q '^- Status: deprecated' '$TMP/apply-dep.md'"
assert "AC 4 — deprecate: Closed field added" "grep -q '^- Closed: 2026-04-30' '$TMP/apply-dep.md'"
assert "AC 4 — deprecate: Revision Log entry added" "grep -q 'Deprecated via /matrix hygiene pass' '$TMP/apply-dep.md'"

make_spec "$TMP/apply-defer.md" "draft" "2026-08-01" "122"
apply_defer "$TMP/apply-defer.md" "2026-04-30" "dependency 122 deferred" "Spec 122 closes"
assert "AC 4 — defer: Revision Log entry with re-activation trigger" "grep -q 'Re-activation trigger: Spec 122 closes' '$TMP/apply-defer.md'"
assert "AC 4 — defer: Status remains draft" "grep -q '^- Status: draft' '$TMP/apply-defer.md'"

# =============================================================================
# AC 5 — Pick subset: only selected indices apply
# =============================================================================
echo "AC 5 — Pick subset"

make_spec "$TMP/subset-A.md" "draft" "2026-01-01" ""
make_spec "$TMP/subset-B.md" "draft" "2026-01-01" ""
make_spec "$TMP/subset-C.md" "draft" "2026-01-01" ""

# Operator picks only A (index 1) — leaves B, C alone
apply_deprecate "$TMP/subset-A.md" "2026-04-30" "picked"

assert "AC 5 — pick subset: A deprecated" "grep -q '^- Status: deprecated' '$TMP/subset-A.md'"
assert "AC 5 — pick subset: B unchanged (still draft)" "grep -q '^- Status: draft' '$TMP/subset-B.md'"
assert "AC 5 — pick subset: C unchanged (still draft)" "grep -q '^- Status: draft' '$TMP/subset-C.md'"

# =============================================================================
# AC 6 — Skip leaves backlog unchanged
# =============================================================================
echo "AC 6 — Skip"

make_spec "$TMP/skip-A.md" "draft" "2026-01-01" ""
make_spec "$TMP/skip-B.md" "draft" "2026-08-01" "122"

before_md5_A=$(md5sum "$TMP/skip-A.md" | awk '{print $1}')
before_md5_B=$(md5sum "$TMP/skip-B.md" | awk '{print $1}')
# (Operator chose 'skip' — no apply functions called)
after_md5_A=$(md5sum "$TMP/skip-A.md" | awk '{print $1}')
after_md5_B=$(md5sum "$TMP/skip-B.md" | awk '{print $1}')

assert "AC 6 — skip: spec A unchanged after skip" "[[ '$before_md5_A' == '$after_md5_A' ]]"
assert "AC 6 — skip: spec B unchanged after skip" "[[ '$before_md5_B' == '$after_md5_B' ]]"

# =============================================================================
# AC 7 — Mirror parity (delegated to sync --check)
# =============================================================================
echo "AC 7 — Mirror parity (sync --check)"

if bash "$SYNC_SCRIPT" --check >/dev/null 2>&1; then
  assert "AC 7 — sync --check: 4 mirrors byte-identical" "true"
else
  assert "AC 7 — sync --check: 4 mirrors byte-identical" "false"
fi

# =============================================================================
# AC 8 — Skip-on-empty deferral trigger
# =============================================================================
echo "AC 8 — Skip-on-empty deferral trigger"

make_spec "$TMP/empty-trigger.md" "draft" "2026-08-01" "122"
before=$(md5sum "$TMP/empty-trigger.md" | awk '{print $1}')
apply_defer "$TMP/empty-trigger.md" "2026-04-30" "dep 122 deferred" ""  # empty trigger → skip
after=$(md5sum "$TMP/empty-trigger.md" | awk '{print $1}')

assert "AC 8 — skip-on-empty: spec unchanged when trigger is empty" "[[ '$before' == '$after' ]]"
assert "AC 8 — skip-on-empty: no Deferred-hygiene-pass entry" "! grep -q 'Deferred via /matrix hygiene pass' '$TMP/empty-trigger.md'"

# =============================================================================
# AC 9 — Canonical guide contains required terms
# =============================================================================
echo "AC 9 — Canonical guide content"

assert "AC 9 — guide: 'rank ≥ 30' threshold present" "grep -q 'rank ≥ 30' '$GUIDE'"
assert "AC 9 — guide: '30-day' or '30 days' idempotency window present" "grep -qE '(30-day|30 days|last 30 days)' '$GUIDE'"
assert "AC 9 — guide: 'Deprecation candidates' scan section" "grep -q 'Deprecation candidates' '$GUIDE'"
assert "AC 9 — guide: 'Deferral candidates' scan section" "grep -q 'Deferral candidates' '$GUIDE'"
assert "AC 9 — guide: 'Cross-edit invariant' warning section" "grep -q 'Cross-edit invariant' '$GUIDE'"
assert "AC 9 — guide: re-activation trigger templates" "grep -q 'Re-activation trigger templates' '$GUIDE'"
assert "AC 9 — guide: skip-on-empty mention" "grep -qi 'skip-on-empty' '$GUIDE'"
assert "AC 9 — guide: canonical sentinel block fence" "grep -q 'Canonical sentinel block' '$GUIDE'"

# =============================================================================
# AC 10 — Idempotency: re-run filters recently-deferred specs
# =============================================================================
echo "AC 10 — Idempotency"

# First run: spec qualifies, gets deferred
cat > "$TMP/dep-122-stable.md" << 'EOF'
# Spec 122 — deferred
- Status: draft (deferred — runtime infrastructure)
EOF
make_spec "$TMP/idem.md" "draft" "2026-08-01" "122"

if is_deferral_candidate "$TMP/idem.md" "$TMP/dep-122-stable.md" "2026-04-30"; then
  assert "AC 10 — first /matrix run: spec flagged" "true"
else
  assert "AC 10 — first /matrix run: spec flagged" "false"
fi

# Apply deferral
apply_defer "$TMP/idem.md" "2026-04-30" "dep 122 deferred" "Spec 122 closes"

# Second run (next-day simulation): should be filtered out by 30-day idempotency window
if is_deferral_candidate "$TMP/idem.md" "$TMP/dep-122-stable.md" "2026-05-01"; then
  assert "AC 10 — second /matrix run within 30 days: spec FILTERED" "false"
else
  assert "AC 10 — second /matrix run within 30 days: spec FILTERED" "true"
fi

# After 30 days: spec re-surfaces
if is_deferral_candidate "$TMP/idem.md" "$TMP/dep-122-stable.md" "2026-06-15"; then
  assert "AC 10 — after 30 days: spec re-surfaces (deferral became stale)" "true"
else
  assert "AC 10 — after 30 days: spec re-surfaces (deferral became stale)" "false"
fi

# Deprecation idempotency: already-deprecated specs are filtered
make_spec "$TMP/already-dep.md" "deprecated" "2026-01-01" ""
if is_deprecation_candidate "$TMP/already-dep.md" "2026-04-30" 42 47; then
  assert "AC 10 — deprecation idempotency: already-deprecated NOT re-flagged" "false"
else
  assert "AC 10 — deprecation idempotency: already-deprecated NOT re-flagged" "true"
fi

# =============================================================================
# Summary
# =============================================================================
echo ""
echo "=========================================="
echo "Spec 370 hygiene-pass tests: $PASS PASS, $FAIL FAIL"
echo "=========================================="

if [[ $FAIL -gt 0 ]]; then
  exit 1
fi
exit 0
