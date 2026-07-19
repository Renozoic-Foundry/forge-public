#!/usr/bin/env bash
# FORGE Stop hook — session-log advisory (Spec 460, NC-2 slice 3)
# At Claude turn end: if the working tree shows changes under spec/code paths
# (docs/specs/, template/, .forge/, .claude/, src/, scripts/) WITHOUT an
# accompanying change under docs/sessions/, soft-warn to stderr citing
# CLAUDE.md hard rule #2 ("every session ends with a session log").
#
# ADVISORY ONLY — exit 0 in all paths; emits no decision JSON; NEVER blocks.
# A missing docs/sessions/ directory is treated the same as an un-updated
# session log: the advisory still fires (DA disposition #3).
# forge:path-literal-ok (comment) — resolved paths used below
#
# Known residual risk (documented in Spec 460 Verification Scope): git status
# --porcelain may miss edge cases (ignored files, edits outside the repo).
# The prose rule in CLAUDE.md remains authoritative; this is a safety net.

# Consume stdin (hook JSON; content unused). Malformed stdin is graceful.
cat >/dev/null 2>&1 || true

# Spec 487: resolve the project root so the advisory inspects the project tree whether
# this hook runs from a Copier-rendered tree or the plugin payload. Fail-open.
_HOOK_DIR=$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)
if [ -n "${_HOOK_DIR:-}" ] && [ -f "$_HOOK_DIR/../lib/resolve-root.sh" ]; then
  # shellcheck source=/dev/null
  . "$_HOOK_DIR/../lib/resolve-root.sh" 2>/dev/null || true
  forge_resolve_roots 2>/dev/null || true
fi

# Fail-open without git or outside a repo — advisory is best-effort.
command -v git >/dev/null 2>&1 || exit 0
PORCELAIN="$(git -C "${FORGE_PROJECT_ROOT:-.}" status --porcelain 2>/dev/null)" || exit 0
[ -n "$PORCELAIN" ] || exit 0

# Spec 575 — resolve process-state paths via forge.paths (classic defaults when unset)
SESSIONS_DIR="docs/sessions"
SPECS_DIR="docs/specs"
_cfg="$(dirname "${BASH_SOURCE[0]:-$0}")/../lib/config.sh"
if [ -f "$_cfg" ]; then
  # shellcheck source=/dev/null
  . "$_cfg"
  PROJECT_DIR="${FORGE_PROJECT_ROOT:-.}" forge_config_load "${FORGE_PROJECT_ROOT:-.}/AGENTS.md" >/dev/null 2>&1 || true
  __resolved="$(PROJECT_DIR="${FORGE_PROJECT_ROOT:-.}" forge_path sessions 2>/dev/null)" && SESSIONS_DIR="$__resolved"
  __resolved="$(PROJECT_DIR="${FORGE_PROJECT_ROOT:-.}" forge_path specs 2>/dev/null)" && SPECS_DIR="$__resolved"
fi

TOUCHED_CODE=false
TOUCHED_LOG=false
while IFS= read -r line; do
  [ -n "$line" ] || continue
  path="${line:3}"
  # Rename entries are "old -> new": take the destination side.
  case "$path" in *" -> "*) path="${path##* -> }" ;; esac
  # git quotes paths containing special characters.
  path="${path#\"}"
  case "$path" in
    "$SESSIONS_DIR"/*) TOUCHED_LOG=true ;;
    "$SPECS_DIR"/* | template/* | .forge/* | .claude/* | src/* | scripts/*) TOUCHED_CODE=true ;;
  esac
done <<<"$PORCELAIN"

if [ "$TOUCHED_CODE" = true ] && [ "$TOUCHED_LOG" = false ]; then
  echo "FORGE advisory (Spec 460): spec/code files changed but no session log under ${SESSIONS_DIR}/ was updated. CLAUDE.md hard rule #2: every session ends with a session log. Run /session." >&2
fi
exit 0
