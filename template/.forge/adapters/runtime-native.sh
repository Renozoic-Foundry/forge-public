#!/usr/bin/env bash
# FORGE runtime-native.sh — Native runtime adapter (git worktree isolation)
# Implements the runtime adapter interface. Sourced by runtime-adapter.sh.
#
# Governance gap: No filesystem permission enforcement in native mode.
# The agent CAN write outside its declared scope. This is logged as a warning.

FORGE_WORKTREE_BASE=""

forge_runtime_spawn() {
  local role="$1"
  local spec_id="$2"
  local working_dir="${3:-$PROJECT_DIR}"

  FORGE_WORKTREE_BASE="${PROJECT_DIR}/.forge/worktrees"
  mkdir -p "$FORGE_WORKTREE_BASE"

  local agent_id="spec-${spec_id}-${role}"
  local worktree_dir="${FORGE_WORKTREE_BASE}/${agent_id}"

  # Log governance gap warning
  echo "WARN: Native runtime — no filesystem permission enforcement. Agent '${role}' can write outside declared scope." >&2
  forge_audit_log "$role" "governance-warning" "Native mode: no filesystem permission enforcement for role ${role}"

  # Create git worktree for isolation
  if [[ -d "$worktree_dir" ]]; then
    echo "Worktree already exists for ${agent_id} — reusing" >&2
  else
    git -C "$working_dir" worktree add "$worktree_dir" -b "forge/${agent_id}" HEAD 2>&1 || {
      echo "ERROR: Failed to create worktree for ${agent_id}" >&2
      return 1
    }
  fi

  echo "Spawned agent: ${agent_id} in ${worktree_dir}" >&2

  # Return the agent_id and working directory
  echo "${agent_id}|${worktree_dir}"
}

forge_runtime_halt() {
  local agent_id="$1"

  # Find the PID from the audit registry
  local pid
  pid="$(grep -o "\"agent_id\":\"${agent_id}\"[^}]*\"pid\":[0-9]*" "$FORGE_PID_FILE" 2>/dev/null | grep -o '"pid":[0-9]*' | cut -d: -f2)"

  if [[ -n "$pid" ]]; then
    if kill -0 "$pid" 2>/dev/null; then
      kill -TERM "$pid" 2>/dev/null
      # Wait briefly for graceful shutdown
      local waited=0
      while kill -0 "$pid" 2>/dev/null && (( waited < 10 )); do
        sleep 1
        (( waited++ ))
      done
      # Force kill if still running
      if kill -0 "$pid" 2>/dev/null; then
        kill -KILL "$pid" 2>/dev/null
      fi
      echo "Agent ${agent_id} halted (PID ${pid})" >&2
    else
      echo "Agent ${agent_id} already stopped (PID ${pid})" >&2
    fi
    forge_audit_unregister_pid "$agent_id" "halted"
  else
    echo "WARN: No PID found for agent ${agent_id}" >&2
  fi

  forge_audit_log "$agent_id" "halt" "Agent halted"
}

forge_runtime_halt_all() {
  echo "Kill switch activated — halting all FORGE agents" >&2
  forge_audit_log "pipeline" "kill-switch" "Halting all agents"

  local pids
  pids="$(forge_audit_get_running_pids)"

  local count=0
  for pid in $pids; do
    if kill -0 "$pid" 2>/dev/null; then
      kill -TERM "$pid" 2>/dev/null
      (( count++ ))
    fi
  done

  # Wait for graceful shutdown
  sleep 2

  # Force kill any stragglers
  for pid in $pids; do
    if kill -0 "$pid" 2>/dev/null; then
      kill -KILL "$pid" 2>/dev/null
    fi
  done

  echo "Halted ${count} agent(s)" >&2
}

forge_runtime_status() {
  local agent_id="$1"

  local pid
  pid="$(grep -o "\"agent_id\":\"${agent_id}\"[^}]*\"pid\":[0-9]*" "$FORGE_PID_FILE" 2>/dev/null | grep -o '"pid":[0-9]*' | cut -d: -f2)"

  if [[ -z "$pid" ]]; then
    echo "unknown"
    return
  fi

  if kill -0 "$pid" 2>/dev/null; then
    echo "running"
  else
    echo "stopped"
  fi
}

forge_runtime_cleanup() {
  local agent_id="$1"

  local worktree_dir="${FORGE_WORKTREE_BASE:-${PROJECT_DIR}/.forge/worktrees}/${agent_id}"

  if [[ -d "$worktree_dir" ]]; then
    git -C "$PROJECT_DIR" worktree remove "$worktree_dir" --force 2>/dev/null || {
      echo "WARN: Could not remove worktree ${worktree_dir} — may need manual cleanup" >&2
    }
    # Clean up the branch
    git -C "$PROJECT_DIR" branch -D "forge/${agent_id}" 2>/dev/null
    echo "Cleaned up worktree: ${agent_id}" >&2
  fi

  forge_audit_log "$agent_id" "cleanup" "Worktree removed"
}
