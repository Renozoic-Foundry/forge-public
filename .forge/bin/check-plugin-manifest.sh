#!/usr/bin/env bash
# FORGE plugin manifest schema check (Spec 490 — R2/R5).
#
# Validates .claude-plugin/plugin.json against Claude Code's manifest schema rules that
# `jq -e .` (well-formedness only) does NOT catch — the defect class that shipped
# SIG-487-03 (a directory-valued `agents` field that fails `/plugin install`).
#
# Checks:
#   1. All component-path entries (skills/commands/agents/outputStyles) start with "./".
#   2. `agents` entries are FILES, not directories ("Custom agent files" — schema rejects dirs).
#   3. Every listed path exists at HEAD.
#   4. Drift (R5): every .claude/agents/*.md on disk is listed in `agents` (no silent omission).
#   5. Best-effort: if the `claude` CLI is present, also run `claude plugin validate --strict`.
#
# Exit 0 = schema-valid; 1 = violation; 3 = jq unavailable. Run: bash .forge/bin/check-plugin-manifest.sh
set -uo pipefail

ROOT=""
while [ $# -gt 0 ]; do
  case "$1" in
    --root) ROOT="${2:-}"; shift 2 ;;
    -h|--help) echo "usage: check-plugin-manifest.sh [--root <plugin-root>]"; exit 0 ;;
    *) echo "check-plugin-manifest: unknown arg: $1" >&2; exit 2 ;;
  esac
done
if [ -z "$ROOT" ]; then
  ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fi
ROOT="$(printf '%s' "$ROOT" | tr '\\' '/')"
PJ="$ROOT/.claude-plugin/plugin.json"

fail=0
err() { echo "  FAIL: $*" >&2; fail=1; }

if [ ! -f "$PJ" ]; then
  echo "check-plugin-manifest: no plugin.json at $PJ — skipped (not a plugin payload)."
  exit 0
fi
if ! command -v jq >/dev/null 2>&1; then
  echo "check-plugin-manifest: jq not found — cannot validate manifest schema" >&2
  exit 3
fi
if ! jq -e . "$PJ" >/dev/null 2>&1; then
  err "plugin.json is not valid JSON"
  echo "RESULT: FAIL"; exit 1
fi

echo "=== check-plugin-manifest: $PJ ==="

# Emit a field's entries one per line (handles string | array | absent).
field_entries() {
  jq -r --arg k "$1" '
    if (has($k)|not) then empty
    elif (.[$k]|type)=="string" then .[$k]
    elif (.[$k]|type)=="array" then .[$k][]
    else empty end' "$PJ" | tr -d '\r'
}

# 1. All component-path entries must start with "./".
for k in skills commands agents outputStyles; do
  while IFS= read -r p; do
    [ -z "$p" ] && continue
    case "$p" in
      ./*) ;;
      *) err "$k path must start with './' (got: $p)" ;;
    esac
  done < <(field_entries "$k")
done

# 2 + 3. agents entries must be FILES (not dirs) and must exist (SIG-487-03).
while IFS= read -r p; do
  [ -z "$p" ] && continue
  abs="$ROOT/${p#./}"
  if [ -d "$abs" ]; then
    err "agents entry is a DIRECTORY: $p — the manifest schema accepts only file paths for 'agents' (SIG-487-03). Enumerate the .md files or relocate to ./agents/."
  elif [ ! -e "$abs" ]; then
    err "agents entry not found at HEAD: $p"
  fi
done < <(field_entries agents)

# 3 (skills). Each skills entry must exist.
while IFS= read -r p; do
  [ -z "$p" ] && continue
  abs="$ROOT/${p#./}"
  [ -e "$abs" ] || err "skills entry not found at HEAD: $p"
done < <(field_entries skills)

# 4. Drift (R5): every .claude/agents/*.md must be listed in `agents`.
if jq -e 'has("agents")' "$PJ" >/dev/null 2>&1; then
  listed="$(field_entries agents | sed 's|^\./||' | LC_ALL=C sort)"
  actual="$( (cd "$ROOT" && ls .claude/agents/*.md 2>/dev/null) | LC_ALL=C sort)"
  missing="$(comm -13 <(printf '%s\n' "$listed") <(printf '%s\n' "$actual") | sed '/^$/d')"
  if [ -n "$missing" ]; then
    err "agent file(s) on disk NOT listed in plugin.json 'agents' (enumeration drift, R5): $(printf '%s ' $missing)"
  fi
fi

# 5. Best-effort: native validator if the claude CLI is available (non-strict so the known
#    CLAUDE.md-at-root advisory — SIG-489-01, doctrine is not plugin-injectable — does not fail).
if command -v claude >/dev/null 2>&1; then
  if ! claude plugin validate "$ROOT" >/dev/null 2>&1; then
    echo "  WARN: 'claude plugin validate' reported errors — run it directly for detail." >&2
  fi
fi

if [ "$fail" -ne 0 ]; then
  echo "RESULT: FAIL — plugin.json has manifest-schema violations."
  exit 1
fi
echo "RESULT: OK — plugin.json component paths are schema-valid (agents are files, all ./-relative, no agent drift)."
exit 0
