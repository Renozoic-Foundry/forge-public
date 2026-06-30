#!/usr/bin/env bash
# Spec 494 — stash-reintroduction lint.
#
# FAILs if any command body introduces a `git stash` (stashing op) that does not
# preserve untracked files via --include-untracked / -u, guarding the EA-086 /
# EA-424 WIP-loss class against re-entry. No such instruction exists in the
# command bodies today, so this passes clean on the current tree (forward guard).
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && cd .. && pwd)"
dirs=(
  "$ROOT/.forge/commands"
  "$ROOT/.claude/commands"
  "$ROOT/template/.forge/commands"
  "$ROOT/template/.claude/commands"
)

violations=0
for d in "${dirs[@]}"; do
  [ -d "$d" ] || continue
  while IFS= read -r hit; do
    [ -n "$hit" ] || continue
    # A stashing op is `git stash` / `git stash push` / `git stash save` (NOT
    # pop/apply/list/show/drop/clear/branch). Unsafe = lacks -u/--include-untracked.
    if echo "$hit" | grep -qE 'git stash\b' \
       && ! echo "$hit" | grep -qE 'git stash (pop|apply|list|show|drop|clear|branch)' \
       && ! echo "$hit" | grep -qE '(--include-untracked|[[:space:]]-u\b)'; then
      echo "  VIOLATION: $hit"
      violations=$((violations + 1))
    fi
  done < <(grep -rnE 'git stash' "$d" 2>/dev/null || true)
done

if [ "$violations" -gt 0 ]; then
  echo "GATE [stash-reintroduction]: FAIL — $violations unsafe \`git stash\` (no --include-untracked) in command bodies."
  exit 1
fi
echo "GATE [stash-reintroduction]: PASS — no unsafe git stash in command bodies."
exit 0
