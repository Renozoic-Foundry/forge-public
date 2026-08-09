#!/usr/bin/env bash
# check-roles-model-consistency.sh — Spec 648 AC3.
#
# Cross-checks every `forge.roles.*.model` value declared inline in AGENTS.md's
# Runtime Configuration YAML block against the corresponding `.claude/agents/*.md`
# frontmatter `model:` line. FAILs on any mismatch — this exists so a well-meaning
# edit toward one surface (e.g. "correcting" AGENTS.md's validator entry back to
# sonnet) cannot silently revert a deliberate per-role tier decision (Spec 462:
# validator intentionally runs haiku) without a visible, mechanical FAIL.
#
# Usage:
#   bash check-roles-model-consistency.sh                # check this repo
#   bash check-roles-model-consistency.sh --root <DIR>   # check a fixture/copied tree
# Exit 0 = PASS (or SKIP — surfaces absent), 1 = FAIL (mismatch or missing file).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

while [ $# -gt 0 ]; do
  case "$1" in
    --root) ROOT="$2"; shift 2 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

AGENTS_MD="$ROOT/AGENTS.md"
AGENTS_DIR="$ROOT/.claude/agents"

if [ ! -f "$AGENTS_MD" ]; then
  echo "SKIP: $AGENTS_MD missing"
  exit 0
fi
if [ ! -d "$AGENTS_DIR" ]; then
  echo "SKIP: $AGENTS_DIR missing"
  exit 0
fi

# role_key (AGENTS.md forge.roles.<key>) -> agent filename stem (.claude/agents/<stem>.md)
ROLE_KEYS="devils_advocate validator"

FAIL=0

extract_agents_model() {
  # $1 = role key. Prints the model value from the role's inline `{ ... model: X ... }`
  # hash on its AGENTS.md line, or nothing if not found.
  grep -E "^[[:space:]]*${1}:[[:space:]]*\{" "$AGENTS_MD" | head -1 \
    | grep -oE 'model:[[:space:]]*[A-Za-z0-9_-]+' | sed -E 's/^model:[[:space:]]*//'
}

extract_frontmatter_model() {
  # $1 = agent file path. Prints the `model:` frontmatter value (between the
  # first two `---` lines), or nothing if not found.
  awk 'BEGIN{n=0} /^---[[:space:]]*$/{n++; if(n==2){exit} next} n==1{print}' "$1" \
    | grep -E '^model:' | head -1 | sed -E 's/^model:[[:space:]]*//'
}

for role in $ROLE_KEYS; do
  file_stem="${role//_/-}"
  file="$AGENTS_DIR/${file_stem}.md"

  agents_model="$(extract_agents_model "$role")"
  if [ -z "$agents_model" ]; then
    echo "FAIL: forge.roles.${role}.model not found in $AGENTS_MD"
    FAIL=1
    continue
  fi

  if [ ! -f "$file" ]; then
    echo "FAIL: $file missing (referenced by forge.roles.${role})"
    FAIL=1
    continue
  fi

  file_model="$(extract_frontmatter_model "$file")"
  if [ -z "$file_model" ]; then
    echo "FAIL: $file has no model: frontmatter field"
    FAIL=1
    continue
  fi

  if [ "$agents_model" != "$file_model" ]; then
    echo "FAIL: forge.roles.${role}.model = ${agents_model} (AGENTS.md) != model: ${file_model} (${file})"
    FAIL=1
    continue
  fi

  echo "PASS: forge.roles.${role}.model = ${agents_model} matches ${file}"
done

if [ "$FAIL" -eq 1 ]; then
  echo "FAIL: role/frontmatter model cross-check found mismatches"
  exit 1
fi

echo "PASS: all forge.roles.*.model values match .claude/agents/*.md frontmatter"
exit 0
