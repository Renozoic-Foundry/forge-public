#!/usr/bin/env bash
# worktree-reconcile.sh — Spec 649 Requirement 3 / AC3, AC3a, AC3b.
#
# ONE shared library, invoked by BOTH /implement and /close, rather than the same logic
# embedded twice in two command bodies (Spec 649 Requirement 6; the validator-pipeline.sh
# precedent). A second copy is how the two surfaces drift.
#
# WHY THIS EXISTS
# ---------------
# `forge.roles.implementer.use_worktree` defaults to `auto`, so implementer agents routinely
# run in isolated git worktrees. Reconciliation was fully manual (list, copy, `worktree remove
# --force`, `branch -D`), and agent-roles-guide.md warns that skipping it "leaves the
# implementation invisible to the rest of /implement's gates ... they all run against the main
# tree." Nothing checked. The measured residue: 11 linked worktrees, ~476 MB, every one pinned
# to a pre-Spec-558 commit and still carrying the deleted template/ tree.
#
# PREVENTION FIRST, DETECTION SECOND (consensus round 1, Maverick Thinker). Detection alone
# treats the symptom while manual-only reconciliation keeps producing residue. So:
#   reconcile  — remove worktrees that provably hold no unique work (stops the next 476 MB)
#   check      — report anything still unreconciled BEFORE gates run against the main tree
#
# SAFETY (all three are load-bearing)
#   1. A worktree with ANY unique unmerged commit is never removed. `git log main..<branch>`
#      must be empty. This is Spec 649's Constraint, not a heuristic.
#   2. A worktree reporting `locked` is NEVER removed, regardless of commit state or pin age
#      (AC3b). The DA gate found a live locked worktree during its own review — its isolated
#      sandbox — so every worktree-isolated run has one, and a naive sweep would target it.
#      `git worktree remove` has its own refusal, but relying on that is relying on a side
#      effect; this is an explicit, tested rule.
#   3. Dirty worktrees (uncommitted edits) are reported, never removed — uncommitted work is
#      exactly what "invisible to the gates" means.
#
# Usage:
#   worktree-reconcile.sh check       # report only; exit 0 clean, 1 if anything unreconciled
#   worktree-reconcile.sh reconcile   # remove provably-safe worktrees, then report the rest
#   worktree-reconcile.sh list        # machine-readable inventory, always exit 0

set -euo pipefail

MODE="${1:-check}"
MAIN_REF="${FORGE_WORKTREE_MAIN_REF:-main}"

# Every worktree except the main one, with its lock state and branch.
# `git worktree list --porcelain` emits stanzas separated by blank lines; the first stanza is
# always the main working tree, which is never a reconciliation candidate.
_inventory() {
    git worktree list --porcelain 2>/dev/null | awk '
        /^worktree /{ wt = substr($0, 10); locked = 0; branch = "" }
        /^locked/    { locked = 1 }
        /^branch /   { branch = substr($0, 8) }
        /^$/         { if (wt != "" && ++n > 1) print wt "\t" locked "\t" branch; wt = "" }
        END          { if (wt != "" && ++n > 1) print wt "\t" locked "\t" branch }
    '
}

# Unique commits on a branch relative to the main ref. Empty output == nothing unique.
_unique_commits() {
    local branch="$1"
    [[ -z "$branch" ]] && { printf 'unknown'; return; }
    git log --oneline "${MAIN_REF}..${branch}" 2>/dev/null | head -5 || true
}

_is_dirty() {
    local wt="$1"
    [[ -n "$(git -C "$wt" status --porcelain 2>/dev/null || true)" ]]
}

REMOVED=0
SKIPPED_LOCKED=0
SKIPPED_UNIQUE=0
SKIPPED_DIRTY=0
UNRECONCILED=0

_report() {
    printf '  %-9s %s\n' "$1" "$2"
}

main() {
    if ! git rev-parse --git-dir >/dev/null 2>&1; then
        echo "worktree-reconcile: not a git repository — skipped."
        return 0
    fi

    local inv
    inv="$(_inventory)"

    if [[ -z "$inv" ]]; then
        [[ "$MODE" != "list" ]] && echo "GATE [worktree-reconcile]: PASS — no linked worktrees."
        return 0
    fi

    while IFS=$'\t' read -r wt locked branch; do
        [[ -z "$wt" ]] && continue

        if [[ "$MODE" == "list" ]]; then
            printf '%s\tlocked=%s\tbranch=%s\n' "$wt" "$locked" "${branch:-none}"
            continue
        fi

        # AC3b — lock check FIRST, before any other rule can reach a removal decision.
        if [[ "$locked" == "1" ]]; then
            _report "LOCKED" "$wt — skipped and reported; never removed (AC3b)"
            SKIPPED_LOCKED=$((SKIPPED_LOCKED + 1))
            UNRECONCILED=$((UNRECONCILED + 1))
            continue
        fi

        if _is_dirty "$wt"; then
            _report "DIRTY" "$wt — uncommitted edits; reported, not removed"
            SKIPPED_DIRTY=$((SKIPPED_DIRTY + 1))
            UNRECONCILED=$((UNRECONCILED + 1))
            continue
        fi

        local uniq
        uniq="$(_unique_commits "$branch")"
        if [[ -n "$uniq" ]]; then
            _report "UNIQUE" "$wt (${branch:-no branch}) — has unmerged commits; retained"
            SKIPPED_UNIQUE=$((SKIPPED_UNIQUE + 1))
            UNRECONCILED=$((UNRECONCILED + 1))
            continue
        fi

        # Provably safe: unlocked, clean, no unique commits.
        if [[ "$MODE" == "reconcile" ]]; then
            if git worktree remove "$wt" 2>/dev/null; then
                _report "REMOVED" "$wt (${branch:-no branch}) — clean, no unique commits"
                REMOVED=$((REMOVED + 1))
            else
                _report "FAILED" "$wt — git worktree remove refused; left in place"
                UNRECONCILED=$((UNRECONCILED + 1))
            fi
        else
            _report "STALE" "$wt (${branch:-no branch}) — reconcilable; run 'reconcile' to remove"
            UNRECONCILED=$((UNRECONCILED + 1))
        fi
    done <<< "$inv"

    [[ "$MODE" == "list" ]] && return 0

    if [[ "$UNRECONCILED" -eq 0 ]]; then
        echo "GATE [worktree-reconcile]: PASS — no unreconciled worktrees (removed=$REMOVED)."
        return 0
    fi

    echo "GATE [worktree-reconcile]: WARN — ${UNRECONCILED} unreconciled worktree(s): locked=${SKIPPED_LOCKED}, dirty=${SKIPPED_DIRTY}, unique-commits=${SKIPPED_UNIQUE}, removed=${REMOVED}."
    echo "  Gates below run against the MAIN tree; work in an unreconciled worktree is invisible to them."
    return 1
}

main "$@"
