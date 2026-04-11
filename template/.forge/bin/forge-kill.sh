#!/usr/bin/env bash
# FORGE Kill Switch — halt all running agents, preserve state
# Delegates to PAL for challenge invalidation when available.
# Usage: forge-kill.sh [--force]
set -euo pipefail

FORGE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_DIR="$(cd "${FORGE_DIR}/.." && pwd)"

source "${FORGE_DIR}/lib/config.sh"
source "${FORGE_DIR}/lib/runtime-adapter.sh"
source "${FORGE_DIR}/lib/audit.sh"
source "${FORGE_DIR}/lib/security.sh"
source "${FORGE_DIR}/lib/logging.sh"

forge_log_init "forge-kill"

FORCE=false
if [[ "${1:-}" == "--force" ]]; then FORCE=true; fi

# Load config and runtime adapter
forge_config_load "${PROJECT_DIR}/AGENTS.md"
forge_runtime_load_adapter

# Find the most recent audit session
LATEST_AUDIT=""
if [[ -d "${PROJECT_DIR}/.forge/audit" ]]; then
  LATEST_AUDIT="$(ls -1d "${PROJECT_DIR}/.forge/audit/"*/ 2>/dev/null | sort -r | head -1)"
fi

if [[ -n "$LATEST_AUDIT" ]]; then
  FORGE_AUDIT_DIR="$LATEST_AUDIT"
  FORGE_AUDIT_LOG="${FORGE_AUDIT_DIR}pipeline.log"
  FORGE_PID_FILE="${FORGE_AUDIT_DIR}pids.json"
fi

forge_log_info "Kill switch activated"
echo "=== FORGE Kill Switch ==="
echo ""

# Halt all running agents
forge_runtime_halt_all

# Invalidate all outstanding security challenges
# Delegates to PAL when available, falls back to local invalidation
forge_security_init "$PROJECT_DIR"
forge_gate_kill

if [[ -n "$FORGE_AUDIT_LOG" && -f "$FORGE_AUDIT_LOG" ]]; then
  forge_audit_log "kill-switch" "activated" "All agents halted. Autonomy reverted to L1."
fi

# Handle --force: remove worktrees
if $FORCE; then
  echo ""
  echo "WARNING: --force will remove all FORGE worktrees."
  read -r -p "Are you sure? (y/N) " confirm
  if [[ "$confirm" =~ ^[Yy]$ ]]; then
    WORKTREE_DIR="${PROJECT_DIR}/.forge/worktrees"
    if [[ -d "$WORKTREE_DIR" ]]; then
      for wt in "$WORKTREE_DIR"/*/; do
        [[ -d "$wt" ]] || continue
        local_name="$(basename "$wt")"
        git -C "$PROJECT_DIR" worktree remove "$wt" --force 2>/dev/null || true
        git -C "$PROJECT_DIR" branch -D "forge/${local_name}" 2>/dev/null || true
        echo "Removed worktree: ${local_name}"
      done
    fi
    echo "All worktrees removed."
  else
    echo "Worktree removal cancelled."
  fi
else
  echo ""
  echo "Worktrees preserved. Run with --force to remove them."
fi

echo ""
echo "Kill switch activated. All FORGE agents halted. Autonomy reverted to L1."
