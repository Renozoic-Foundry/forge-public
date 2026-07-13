#!/usr/bin/env bash
# FORGE SessionStart hook — state-snapshot + spec-implying hint (Spec 460, NC-2 slice 3)
# Prints a compact /now-style summary to stdout at session open: active spec,
# active tab, unreviewed digest count, last evolve date. When NO
# .forge/state/implementing.json exists, additionally emits a one-line
# /spec-or-/explore hint at the session's highest-attention moment.
#
# NEVER blocks: exit 0 in all paths. This is a state-snapshot hook, NOT
# enforcement — see docs/process-kit/hook-coverage.md (Slice 3).
#
# The hint fires SOLELY on the absence of implementing.json. It MUST NOT scan
# prompt text or any operator-typed content (Spec 460 constraint — the dropped
# UserPromptSubmit hook had exactly that false-positive surface).

# Consume stdin (Claude Code delivers hook JSON; content is unused — the
# filesystem is the only input). Malformed or empty stdin is therefore
# inherently graceful.
cat >/dev/null 2>&1 || true

# Spec 487: resolve the project root and operate from it, so the project-state /
# docs reads below work whether this hook is invoked from a Copier-rendered tree or
# the plugin payload (the script may live in the payload while state lives in the
# project). Fail-open: if resolution fails, cd "." is a no-op (original behavior).
_HOOK_DIR=$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)
if [ -n "${_HOOK_DIR:-}" ] && [ -f "$_HOOK_DIR/../lib/resolve-root.sh" ]; then
  # shellcheck source=/dev/null
  . "$_HOOK_DIR/../lib/resolve-root.sh" 2>/dev/null || true
  forge_resolve_roots 2>/dev/null || true
fi
cd "${FORGE_PROJECT_ROOT:-.}" 2>/dev/null || true

# --- active spec (from .forge/state/implementing.json) ---
SPEC="(none)"
if [ -f ".forge/state/implementing.json" ]; then
  if command -v jq >/dev/null 2>&1; then
    SPEC="$(jq -r '.spec // "(unknown)"' .forge/state/implementing.json 2>/dev/null || echo "(unknown)")"
  else
    SPEC="$(sed -n 's/.*"spec"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' .forge/state/implementing.json | head -1)"
  fi
  [ -n "$SPEC" ] || SPEC="(unknown)"
fi

# --- active tab (most recently modified .forge/state/active-tab-*.json marker;
#     glob convention per Spec 353 — DA disposition #1) ---
TAB="(none)"
MARKER=""
NEWEST=0
for f in .forge/state/active-tab-*.json; do
  [ -e "$f" ] || continue
  m="$(stat -c %Y "$f" 2>/dev/null || stat -f %m "$f" 2>/dev/null || echo 0)"
  if [ "$m" -ge "$NEWEST" ]; then NEWEST="$m"; MARKER="$f"; fi
done
if [ -n "$MARKER" ]; then
  if command -v jq >/dev/null 2>&1; then
    TAB="$(jq -r '.label // "(unknown)"' "$MARKER" 2>/dev/null || echo "(unknown)")"
  else
    TAB="$(sed -n 's/.*"label"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$MARKER" | head -1)"
  fi
  [ -n "$TAB" ] || TAB="(unknown)"
fi

# --- unreviewed digests (files in docs/digests/ absent from reviewed.md) ---
DIGESTS=0
if [ -d "docs/digests" ]; then
  for f in docs/digests/*.md docs/digests/*.pdf; do
    [ -e "$f" ] || continue
    base="$(basename "$f")"
    [ "$base" = "reviewed.md" ] && continue
    if [ -f "docs/digests/reviewed.md" ] && grep -qF "$base" docs/digests/reviewed.md 2>/dev/null; then
      continue
    fi
    DIGESTS=$((DIGESTS + 1))
  done
fi

# --- last evolve (newest session log carrying a "Last evolve" line) ---
EVOLVE="(unknown)"
LOGS=(docs/sessions/2[0-9]*.md)
if [ -e "${LOGS[0]:-}" ]; then
  for ((i = ${#LOGS[@]} - 1; i >= 0; i--)); do
    d="$(grep -i "last evolve" "${LOGS[$i]}" 2>/dev/null | grep -o '[0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}' | head -1)"
    if [ -n "$d" ]; then EVOLVE="$d"; break; fi
  done
fi

# --- doctor currency (Spec 520 — one-line staleness surface at session start) ---
# Best-effort and fast: --summary reads @{upstream} without fetching. Absent script
# or empty output degrades to no line (this hook NEVER blocks).
DOCTOR_LINE=""
if [ -f ".forge/bin/forge-doctor.sh" ]; then
  DOCTOR_LINE="$(bash .forge/bin/forge-doctor.sh --summary 2>/dev/null | head -1)"
fi

echo "FORGE session snapshot:"
echo "  active spec: $SPEC"
echo "  active tab: $TAB"
echo "  unreviewed digests: $DIGESTS"
echo "  last evolve: $EVOLVE"
if [ -n "$DOCTOR_LINE" ]; then
  echo "  $DOCTOR_LINE"
fi

if [ ! -f ".forge/state/implementing.json" ]; then
  echo "  tip: no active spec — consider /spec or /explore before editing code/docs"
fi
exit 0
