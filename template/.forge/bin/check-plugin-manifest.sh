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
#   7. Hooks parity root<->template with a sha256-pinned expected-divergence pair (Spec 535).
#   8. plugin.json lockstep: version+homepage equality root == template == public (Spec 535).
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

# 7. Hooks parity root↔template (Spec 535 — SIG-518-01). DETECTION-ONLY: the two payloads
#    deliberately diverge in posture (root/plugin = Spec 488 fail-closed signed verifier +
#    full PreToolUse guard chain; template renders = Spec 463 decorative posture, because an
#    unsigned consumer render carrying the fail-closed verifier would brick SessionStart).
#    That divergence is PINNED by sha256 below — any further change to EITHER side of the
#    pinned pair fails this gate and forces a re-review of the posture split; any file
#    present on one side only, or drifted outside the pinned pair, fails immediately.
#    Skipped when template/ is absent (consumer payload shape).
HOOKS_ROOT="$ROOT/.claude-plugin/hooks"
HOOKS_TPL="$ROOT/template/.claude-plugin/hooks"
if [ -d "$HOOKS_TPL" ] && [ -d "$HOOKS_ROOT" ]; then
  echo "=== check-plugin-manifest: hooks parity root<->template (Spec 535) ==="
  # Pinned expected-divergence pair: "<basename> <root-sha256> <template-sha256>"
  # Hashes are LF-normalized (CR stripped) so Windows autocrlf checkouts and Linux CI
  # compute the same digest (Spec 549 — the original hooks.json pin was minted from a
  # CRLF working copy and failed every LF checkout on CI).
  PINNED="hooks.json df27c7f14baa0418479e46a1bb76d6124b45fa877f1c13097aba21f9faa7f92f a615eeafbc72297f3a8287610ff076a19879ad8535dfd7c70bad6026520d5898
session-start-integrity.sh 4e3cd42bbc617022f6c778c2d4366cab6d6adce39579cddddf3866f0bbfc75d5 164d6a778eaf5373641e99b54782f5f998434ce66464db0f803b2b3c379a18e4"
  for f in "$HOOKS_ROOT"/* "$HOOKS_TPL"/*; do
    [ -e "$f" ] || continue
    base="$(basename "$f")"
    rf="$HOOKS_ROOT/$base"; tf="$HOOKS_TPL/$base"
    if [ ! -f "$rf" ]; then err "hooks parity: $base exists in template/ but not root (.claude-plugin/hooks/)"; continue; fi
    if [ ! -f "$tf" ]; then err "hooks parity: $base exists in root but not template/.claude-plugin/hooks/"; continue; fi
    pin="$(printf '%s\n' "$PINNED" | grep "^$base " || true)"
    rh="$(tr -d '\r' < "$rf" | sha256sum | awk '{print $1}')"
    th="$(tr -d '\r' < "$tf" | sha256sum | awk '{print $1}')"
    if [ -n "$pin" ]; then
      want_rh="$(printf '%s' "$pin" | awk '{print $2}')"
      want_th="$(printf '%s' "$pin" | awk '{print $3}')"
      if [ "$rh" != "$want_rh" ] || [ "$th" != "$want_th" ]; then
        err "hooks parity: pinned divergence pair changed for $base (root ${rh:0:8}.. vs pinned ${want_rh:0:8}..; template ${th:0:8}.. vs pinned ${want_th:0:8}..) — re-review the Spec 535 posture split and re-pin"
      fi
    elif [ "$rh" != "$th" ]; then
      err "hooks parity: $base drifted between root and template (not on the pinned-divergence list)"
    fi
  done
else
  echo "check-plugin-manifest: no template/.claude-plugin/hooks under root — hooks parity skipped (consumer payload shape)."
fi

# 8. plugin.json lockstep root == template == public (Spec 535 — SIG-520-01). Version and
#    homepage must agree across the three copies; the value-vs-release-tag truth check lives
#    in scripts/cut-release.sh Step 7b (asserts public/ == the tag being cut). Equality here
#    is ownership-free — compatible with hand-edited or future generated plugin.json.
TPL_PJ="$ROOT/template/.claude-plugin/plugin.json"
PUB_PJ="$ROOT/public/.claude-plugin/plugin.json"
if [ -f "$TPL_PJ" ]; then
  echo "=== check-plugin-manifest: plugin.json lockstep (Spec 535) ==="
  root_v="$(jq -r '.version // ""' "$PJ")"; root_h="$(jq -r '.homepage // ""' "$PJ")"
  for other in "$TPL_PJ" "$PUB_PJ"; do
    [ -f "$other" ] || continue
    o_v="$(jq -r '.version // ""' "$other")"; o_h="$(jq -r '.homepage // ""' "$other")"
    if [ "$o_v" != "$root_v" ]; then
      err "plugin.json lockstep: version drift — root=$root_v vs $other=$o_v"
    fi
    if [ "$o_h" != "$root_h" ]; then
      err "plugin.json lockstep: homepage drift — root=$root_h vs $other=$o_h"
    fi
  done
fi

# 9. Best-effort: native validator if the claude CLI is available (non-strict so the known
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
