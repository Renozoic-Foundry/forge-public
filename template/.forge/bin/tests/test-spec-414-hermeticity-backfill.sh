#!/usr/bin/env bash
# test-spec-414-hermeticity-backfill.sh — Spec 414
#
# Runs assert-hermetic-dry-run against each FORGE-shipped script with a
# `--dry-run` flag identified as non-compliant by Spec 404's audit:
#   1. scripts/safety-backfill-audit.sh        (Spec 387)
#   2. scripts/backfill-valid-until.sh         (Spec 363)
#   3. .forge/bin/forge-sync-commands.sh       (Spec 076 / 357)
#   4. .forge/bin/forge-sync-cross-level.sh    (Spec 270)
#   5. .forge/bin/forge-orchestrate.sh         (Spec 269)  -- SKIP (see reason)
#   6. .forge/bin/forge-install.sh             (Spec 077 / 175) -- SKIP (see reason)
#
# Per Spec 414:
#   AC2: emits one trace line per in-scope script regardless of outcome so all
#        6 names appear in stdout (self-verification of harness coverage).
#   AC3: per-script PASS/FAIL/SKIP. SKIP requires a specific missing-dependency
#        reason. >2 SKIPs of 6 fails the harness.
#   AC5: any FAIL must have a follow-up bug-fix spec ID recorded in the owning
#        spec's Revision Log before /close.
#
# Hermeticity definition: the helper hashes the staging dir before/after the
# command runs; mutation = FAIL. The helper's scope is intra-staging-dir only
# (see DA findings recorded in Spec 414 — out-of-staging-dir leaks to
# `.forge/sessions/`, `/tmp`, etc. are not detected; that gap is a separate
# follow-up class).

set -uo pipefail

FORGE_SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
HELPER="${FORGE_SRC}/.forge/bin/tests/lib/assert-hermetic-dry-run.sh"
# shellcheck source=lib/assert-hermetic-dry-run.sh
source "$HELPER"

TMPROOT="${TMPDIR:-${TEMP:-/tmp}}/spec-414-hermetic-$$"
mkdir -p "$TMPROOT"
trap 'rm -rf "$TMPROOT"' EXIT

PASS_COUNT=0
FAIL_COUNT=0
SKIP_COUNT=0
RESULTS=()

# Stage the FORGE source tree (excluding .git, tmp, node_modules, .forge/state)
# into a writable copy. Each per-script test gets its own fresh staging dir.
stage_tree() {
    local dest="$1"
    mkdir -p "$dest"
    if command -v rsync >/dev/null 2>&1; then
        rsync -a \
            --exclude='.git/' \
            --exclude='node_modules/' \
            --exclude='tmp/' \
            --exclude='.forge/state/' \
            "${FORGE_SRC}/" "${dest}/"
    else
        (cd "$FORGE_SRC" && tar -cf - \
            --exclude='./.git' \
            --exclude='./node_modules' \
            --exclude='./tmp' \
            --exclude='./.forge/state' \
            .) | (cd "$dest" && tar -xf -)
    fi
}

trace() {
    printf 'TEST %s — %s\n' "$1" "$2"
}

record_pass() {
    PASS_COUNT=$((PASS_COUNT + 1))
    RESULTS+=("PASS|$1|")
    trace "$1" "PASS"
}

record_fail() {
    FAIL_COUNT=$((FAIL_COUNT + 1))
    RESULTS+=("FAIL|$1|$2")
    trace "$1" "FAIL — $2"
}

record_skip() {
    SKIP_COUNT=$((SKIP_COUNT + 1))
    RESULTS+=("SKIP|$1|$2")
    trace "$1" "SKIP — $2"
}

# --- Per-script tests ---

test_safety_backfill_audit() {
    local script="scripts/safety-backfill-audit.sh"
    local stage="${TMPROOT}/stage-safety-audit"
    local logf="${TMPROOT}/safety-audit.log"
    stage_tree "$stage"
    if assert_hermetic_dry_run "$stage" -- bash "${stage}/${script}" --dry-run >"$logf" 2>&1; then
        record_pass "$script"
    else
        record_fail "$script" "staging dir mutated; see ${logf}"
    fi
}

test_backfill_valid_until() {
    local script="scripts/backfill-valid-until.sh"
    local stage="${TMPROOT}/stage-backfill-validuntil"
    local logf="${TMPROOT}/backfill-validuntil.log"
    stage_tree "$stage"
    if assert_hermetic_dry_run "$stage" -- bash "${stage}/${script}" --dry-run >"$logf" 2>&1; then
        record_pass "$script"
    else
        record_fail "$script" "staging dir mutated; see ${logf}"
    fi
}

test_forge_sync_commands() {
    local script=".forge/bin/forge-sync-commands.sh"
    local stage="${TMPROOT}/stage-sync-commands"
    local logf="${TMPROOT}/sync-commands.log"
    stage_tree "$stage"
    if assert_hermetic_dry_run "$stage" -- bash "${stage}/${script}" --dry-run --scope project >"$logf" 2>&1; then
        record_pass "$script"
    else
        record_fail "$script" "staging dir mutated; see ${logf}"
    fi
}

test_forge_sync_cross_level() {
    local script=".forge/bin/forge-sync-cross-level.sh"
    local stage="${TMPROOT}/stage-sync-crosslevel"
    local logf="${TMPROOT}/sync-crosslevel.log"
    stage_tree "$stage"
    if assert_hermetic_dry_run "$stage" -- bash "${stage}/${script}" --dry-run >"$logf" 2>&1; then
        record_pass "$script"
    else
        record_fail "$script" "staging dir mutated; see ${logf}"
    fi
}

test_forge_orchestrate() {
    local script=".forge/bin/forge-orchestrate.sh"
    record_skip "$script" "requires --spec NNN argument plus .forge/sessions/ session-state initialization outside CI scope; specific blocker = orchestrator session-init prerequisite (Spec 269)"
}

test_forge_install() {
    local script=".forge/bin/forge-install.sh"
    record_skip "$script" "requires Copier-rendered target directory with .copier-answers.yml; specific blocker = target-dir bootstrap outside FORGE source tree (Spec 077)"
}

# --- Main ---

echo "=== Spec 414 dry-run hermeticity backfill ==="
echo "FORGE_SRC: $FORGE_SRC"
echo "TMPROOT:   $TMPROOT"
echo ""

test_safety_backfill_audit
test_backfill_valid_until
test_forge_sync_commands
test_forge_sync_cross_level
test_forge_orchestrate
test_forge_install

echo ""
echo "=== Summary ==="
echo "PASS: ${PASS_COUNT}  FAIL: ${FAIL_COUNT}  SKIP: ${SKIP_COUNT}  (of 6 in-scope scripts)"

# Self-verification per AC2: every expected script must appear in RESULTS.
EXPECTED=(
    "scripts/safety-backfill-audit.sh"
    "scripts/backfill-valid-until.sh"
    ".forge/bin/forge-sync-commands.sh"
    ".forge/bin/forge-sync-cross-level.sh"
    ".forge/bin/forge-orchestrate.sh"
    ".forge/bin/forge-install.sh"
)
for e in "${EXPECTED[@]}"; do
    found=0
    for r in "${RESULTS[@]}"; do
        case "$r" in
            *"|${e}|"*) found=1; break ;;
        esac
    done
    if [ "$found" -ne 1 ]; then
        echo "SELF-VERIFY FAIL: missing trace for ${e}" >&2
        exit 3
    fi
done

# Per Spec 414 AC3 / Req 5: SKIP cap is 2 of 6.
if [ "$SKIP_COUNT" -gt 2 ]; then
    echo "HARNESS FAIL: SKIP count (${SKIP_COUNT}) exceeds Spec 414 cap (2 of 6)." >&2
    exit 2
fi

if [ "$FAIL_COUNT" -gt 0 ]; then
    echo "Hermeticity FAIL recorded for ${FAIL_COUNT} script(s). Per AC5, file follow-up bug-fix specs and record their IDs in each owning spec's Revision Log before /close." >&2
    exit 1
fi

echo "All in-scope scripts PASS or SKIP-with-reason."
exit 0
