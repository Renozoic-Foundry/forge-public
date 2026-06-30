#!/usr/bin/env bash
# FORGE detective audit (Spec 489 D5 / R5 / AC5) — the ONE residual RENDERED hook.
#
# Phase D removes the rendered framework gate-hooks and ships them via the signed plugin. This hook is
# deliberately NOT removed and NOT under the excluded `.forge/{bin,lib}` — it lives at `.forge/` root so
# it survives the Copier-shrink and is present in the exact state it must catch. It is self-contained
# (coreutils only) so it runs even when the framework payload is absent.
#
# It FAILS LOUD when NEITHER enforcement path is active:
#   (a) rendered framework gate-hooks registered in this project's .claude/settings.json, OR
#   (b) a FORGE plugin installed (CLAUDE_PLUGIN_ROOT set with a plugin manifest).
# If neither → the session has no FORGE enforcement → emit a machine-parseable signal + exit non-zero.
set -uo pipefail

signal() { echo "[forge:neither-path] SIGNAL=$1 severity=$2" >&2; }

# (b) plugin path active? CLAUDE_PLUGIN_ROOT set and a plugin manifest present.
plugin_active=0
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ]; then
  cpr="$(printf '%s' "$CLAUDE_PLUGIN_ROOT" | tr '\\' '/')"
  [ -f "$cpr/.claude-plugin/plugin.json" ] && plugin_active=1
fi

# (a) rendered path active? framework gate-hooks present in this project's settings.json.
# This script lives at <project>/.forge/check-neither-path.sh → project root is one level up.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SETTINGS="$PROJECT_ROOT/.claude/settings.json"
rendered_active=0
if [ -f "$SETTINGS" ] && grep -qE 'check-edit-gate|check-commit-guard|check-session-start|check-role-permissions|check-authority-guard|check-stop' "$SETTINGS" 2>/dev/null; then
  rendered_active=1
fi

if [ "$plugin_active" -eq 0 ] && [ "$rendered_active" -eq 0 ]; then
  signal "neither-path-enforcing" "critical"
  {
    echo "[forge:neither-path] No FORGE enforcement is active: the rendered gate-hooks are absent AND no plugin is installed."
    echo "[forge:neither-path] Restore enforcement before proceeding — install the FORGE plugin:"
    echo "[forge:neither-path]   claude plugin install ./   (from a forge-public checkout)"
    echo "[forge:neither-path] or restore the rendered hooks (.forge/lib/migration-snapshot.sh restore)."
  } >&2
  exit 1
fi
exit 0
