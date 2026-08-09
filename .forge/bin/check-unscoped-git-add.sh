#!/usr/bin/env bash
# check-unscoped-git-add.sh — Spec 668 lint gate.
#
# Flags any unqualified whole-tree `git add` in .forge/commands/*.md: `git add -A`,
# a bare `git add .` (not a specific dotfile like `.gitignore`), or `git add -u`. Each
# sweeps the ENTIRE working tree into a FORGE-authored commit, risking the SIG-435
# defect class (a commit capturing unrelated work) that Spec 494/647/668 progressively
# closed for /onboarding, /configure, and /forge init.
#
# Allowlist: a match is not flagged when the SAME LINE also carries a negation word
# (never / do not / don't / must not) — that line is DOCTRINE forbidding the pattern
# (close.md, forge-stoke.md), not a use of it. Spec 668 Constraints: those lines must
# NOT be edited to "fix" this — allowlisting them here is the correct response.
#
# Usage: check-unscoped-git-add.sh [--root <dir>]
# Exit 0 = clean (or no .forge/commands/ under --root); 1 = unqualified use(s) found.
set -uo pipefail

ROOT="."
while [ $# -gt 0 ]; do
  case "$1" in
    --root) ROOT="${2:-.}"; shift 2 ;;
    -h|--help) echo "usage: check-unscoped-git-add.sh [--root <dir>]"; exit 0 ;;
    *) echo "check-unscoped-git-add: unknown arg: $1" >&2; exit 2 ;;
  esac
done

CMD_DIR="$ROOT/.forge/commands"
if [ ! -d "$CMD_DIR" ]; then
  echo "check-unscoped-git-add: no $CMD_DIR — skipped."
  exit 0
fi

NEGATION_RE='(never|do not|don'"'"'t|must not)'
PATTERN_RE='git[[:space:]]+add[[:space:]]+(-A\b|-u\b|\.([[:space:]]|`|$))'

fail=0
for f in "$CMD_DIR"/*.md; do
  [ -e "$f" ] || continue
  while IFS= read -r matchline; do
    [ -z "$matchline" ] && continue
    lineno="${matchline%%:*}"
    content="${matchline#*:}"
    if printf '%s' "$content" | grep -qiE "$NEGATION_RE"; then
      continue
    fi
    echo "  FAIL: $f:$lineno: unqualified whole-tree git add — $content"
    fail=1
  done < <(grep -nE "$PATTERN_RE" "$f" || true)
done

if [ "$fail" -ne 0 ]; then
  echo "RESULT: FAIL — unqualified whole-tree git add found (see above). Use exact-path staging (Spec 494/668 convention) instead."
  exit 1
fi
echo "RESULT: OK — no unqualified whole-tree git add in $CMD_DIR."
exit 0
