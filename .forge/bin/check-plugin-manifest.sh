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
#   5. Marketplace (Spec 527): when .claude-plugin/marketplace.json is present under --root,
#      validate it minimal-structurally (valid JSON; name, owner.name; plugins[] entries each
#      with name + source; each source resolves to a directory containing .claude-plugin/
#      plugin.json). Absent marketplace.json is a SKIP, not a failure. Full schema authority
#      stays with `claude plugin validate` (MT consensus 2026-07-07 — no parallel validator).
#   7. Hooks pin, single-sided (Spec 535 as reshaped by Spec 558): root .claude-plugin/hooks
#      files are sha256-pinned; any change fails the gate and forces a posture re-review.
#   8. plugin.json lockstep: version+homepage equality root == public (Spec 535/558).
#   9. Best-effort: if the `claude` CLI is present, also run `claude plugin validate --strict`.
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

# 5. Marketplace manifest (Spec 527) — minimal-structural checks only; authoritative schema
#    validation remains `claude plugin validate` (step 6).
MP="$ROOT/.claude-plugin/marketplace.json"
if [ -f "$MP" ]; then
  echo "=== check-plugin-manifest: $MP ==="
  if ! jq -e . "$MP" >/dev/null 2>&1; then
    err "marketplace.json is not valid JSON"
  else
    jq -e '.name | strings' "$MP" >/dev/null 2>&1 || err "marketplace.json missing required field: name"
    jq -e '.owner.name | strings' "$MP" >/dev/null 2>&1 || err "marketplace.json missing required field: owner.name"
    if ! jq -e '.plugins | arrays and length > 0' "$MP" >/dev/null 2>&1; then
      err "marketplace.json missing required field: plugins (non-empty array)"
    else
      n="$(jq '.plugins | length' "$MP")"
      i=0
      while [ "$i" -lt "$n" ]; do
        jq -e --argjson i "$i" '.plugins[$i].name | strings' "$MP" >/dev/null 2>&1 \
          || err "marketplace.json missing required field: plugins[$i].name"
        if ! jq -e --argjson i "$i" '.plugins[$i].source | strings' "$MP" >/dev/null 2>&1; then
          err "marketplace.json missing required field: plugins[$i].source"
        else
          src="$(jq -r --argjson i "$i" '.plugins[$i].source' "$MP")"
          srcdir="$ROOT/${src#./}"
          if [ ! -d "$srcdir" ]; then
            err "marketplace.json plugins[$i].source does not resolve to a directory: $src"
          elif [ ! -f "$srcdir/.claude-plugin/plugin.json" ]; then
            err "marketplace.json plugins[$i].source has no plugin manifest at $src.claude-plugin/plugin.json"
          fi
        fi
        i=$((i+1))
      done
    fi
  fi
else
  echo "check-plugin-manifest: no marketplace.json at $MP — marketplace checks skipped."
fi

# 7. Hooks pin, single-sided (Spec 535 — SIG-518-01; reshaped by Spec 558). The Copier
#    template twin was deleted, so the former root<->template divergence pin collapses to
#    a single-sided sha256 pin on the root payload hooks: the fail-closed signed verifier
#    chain (Spec 488) must not change silently. Any content change to a pinned file — or
#    any unpinned file appearing in .claude-plugin/hooks/ — fails this gate and forces a
#    deliberate re-pin. Hashes are LF-normalized (CR stripped) so Windows autocrlf
#    checkouts and Linux CI compute the same digest (Spec 549).
#    Skipped when .claude-plugin/hooks is absent (consumer payload shape).
HOOKS_ROOT="$ROOT/.claude-plugin/hooks"
if [ -d "$HOOKS_ROOT" ]; then
  echo "=== check-plugin-manifest: hooks pin, single-sided (Spec 535/558) ==="
  # Pinned: "<basename> <root-sha256>"
  PINNED="hooks.json 9027f6fa7218044fbc56ed3fe47010e54438a829e98c6714a96c54c237ec7c6b
session-start-integrity.sh 4e3cd42bbc617022f6c778c2d4366cab6d6adce39579cddddf3866f0bbfc75d5"
  for f in "$HOOKS_ROOT"/*; do
    [ -e "$f" ] || continue
    base="$(basename "$f")"
    pin="$(printf '%s\n' "$PINNED" | grep "^$base " || true)"
    if [ -z "$pin" ]; then
      err "hooks pin: $base present in .claude-plugin/hooks/ but not on the pinned list — pin it deliberately or remove it"
      continue
    fi
    rh="$(tr -d '\r' < "$f" | sha256sum | awk '{print $1}')"
    want_rh="$(printf '%s' "$pin" | awk '{print $2}')"
    if [ "$rh" != "$want_rh" ]; then
      err "hooks pin: $base changed (${rh:0:8}.. vs pinned ${want_rh:0:8}..) — re-review the Spec 488 fail-closed hook chain and re-pin"
    fi
  done
  # Pinned files must actually exist (a deleted hook is as dangerous as a changed one).
  for base in hooks.json session-start-integrity.sh; do
    if [ ! -f "$HOOKS_ROOT/$base" ]; then
      err "hooks pin: pinned file $base missing from .claude-plugin/hooks/"
    fi
  done
else
  echo "check-plugin-manifest: no .claude-plugin/hooks under root — hooks pin skipped (consumer payload shape)."
fi

# 8. plugin.json lockstep root == public (Spec 535 — SIG-520-01; template copy retired by
#    Spec 558). Version and homepage must agree across the two remaining copies; the
#    value-vs-release-tag truth check lives in scripts/cut-release.sh Step 7b (asserts
#    public/ == the tag being cut). Equality here is ownership-free — compatible with
#    hand-edited or future generated plugin.json.
PUB_PJ="$ROOT/public/.claude-plugin/plugin.json"
if [ -f "$PUB_PJ" ]; then
  echo "=== check-plugin-manifest: plugin.json lockstep (Spec 535/558) ==="
  root_v="$(jq -r '.version // ""' "$PJ")"; root_h="$(jq -r '.homepage // ""' "$PJ")"
  o_v="$(jq -r '.version // ""' "$PUB_PJ")"; o_h="$(jq -r '.homepage // ""' "$PUB_PJ")"
  if [ "$o_v" != "$root_v" ]; then
    err "plugin.json lockstep: version drift — root=$root_v vs $PUB_PJ=$o_v"
  fi
  if [ "$o_h" != "$root_h" ]; then
    err "plugin.json lockstep: homepage drift — root=$root_h vs $PUB_PJ=$o_h"
  fi
fi

# 9. Best-effort: native validator if the claude CLI is available (non-strict so the known
#    CLAUDE.md-at-root advisory — SIG-489-01, doctrine is not plugin-injectable — does not fail).
#    FORGE_SKIP_NATIVE_VALIDATE=1 skips it (hermetic fixture runs — headless `claude plugin
#    validate` can hang; Spec 558 fixture reshape).
if [ "${FORGE_SKIP_NATIVE_VALIDATE:-0}" != "1" ] && command -v claude >/dev/null 2>&1; then
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
