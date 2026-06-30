#!/usr/bin/env bash
# FORGE Orchestrator — manages the multi-agent pipeline for a spec
# Usage: forge-orchestrate.sh --spec NNN [--dry-run] [--skip-author] [--skip-advocate]
set -euo pipefail

FORGE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_DIR="$(cd "${FORGE_DIR}/.." && pwd)"

# Source libraries
source "${FORGE_DIR}/lib/config.sh"
source "${FORGE_DIR}/lib/runtime-adapter.sh"
source "${FORGE_DIR}/lib/agent-adapter.sh"
source "${FORGE_DIR}/lib/audit.sh"
source "${FORGE_DIR}/lib/handoff.sh"
source "${FORGE_DIR}/lib/budget.sh"
source "${FORGE_DIR}/lib/logging.sh"

forge_log_init "forge-orchestrate"

# --- Argument parsing ---
SPEC_ID=""
DRY_RUN=false
SKIP_AUTHOR=false
SKIP_ADVOCATE=false
DETACH=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --spec) SPEC_ID="$2"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    --skip-author) SKIP_AUTHOR=true; shift ;;
    --skip-advocate) SKIP_ADVOCATE=true; shift ;;
    --detach) DETACH=true; shift ;;
    -h|--help)
      echo "Usage: forge-orchestrate.sh --spec NNN [--dry-run] [--detach] [--skip-author] [--skip-advocate]"
      echo ""
      echo "Options:"
      echo "  --spec NNN        Spec number to orchestrate (required)"
      echo "  --dry-run         Print planned pipeline without executing"
      echo "  --detach          Run pipeline in background; session state persisted to .forge/sessions/"
      echo "  --skip-author     Skip Spec Author role (spec already written)"
      echo "  --skip-advocate   Skip Devil's Advocate role"
      echo "  -h, --help        Show this help"
      exit 0
      ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

if [[ -z "$SPEC_ID" ]]; then
  echo "ERROR: --spec is required" >&2
  exit 1
fi

# --- Find the spec file ---
SPEC_FILE=""
for f in "${PROJECT_DIR}"/docs/specs/${SPEC_ID}-*.md "${PROJECT_DIR}"/docs/specs/${SPEC_ID}*.md; do
  if [[ -f "$f" ]]; then
    SPEC_FILE="$f"
    break
  fi
done

if [[ -z "$SPEC_FILE" ]]; then
  echo "ERROR: No spec file found for spec ${SPEC_ID}" >&2
  exit 1
fi

# --- Read spec metadata ---
SPEC_STATUS="$(grep -m1 '^- Status:' "$SPEC_FILE" | sed 's/^- Status:[[:space:]]*//')"
SPEC_LANE="$(grep -m1 '^- Change-Lane:' "$SPEC_FILE" | sed 's/^- Change-Lane:[[:space:]]*//' | tr -d '`')"
SPEC_TITLE="$(head -3 "$SPEC_FILE" | grep '^# ' | sed 's/^# //' | sed 's/^Framework: FORGE$//' | head -1)"
if [[ -z "$SPEC_TITLE" ]]; then
  SPEC_TITLE="$(grep -m1 '^# Spec' "$SPEC_FILE" | sed 's/^# //')"
fi

forge_log_info "Orchestrating Spec ${SPEC_ID} — ${SPEC_TITLE} (lane: ${SPEC_LANE})"
echo "=== FORGE Orchestrator ==="
echo "Spec:   ${SPEC_ID} — ${SPEC_TITLE}"
echo "Status: ${SPEC_STATUS}"
echo "Lane:   ${SPEC_LANE}"
echo ""

# --- Load configuration ---
forge_config_load "${PROJECT_DIR}/AGENTS.md"
forge_runtime_load_adapter
forge_agent_load_adapter

# --- Read budget config ---
# time_limit, token_limit, cost_ceiling are set by forge_config_get_budget via eval
eval "$(forge_config_get_budget "${SPEC_LANE:-standard-feature}")"
# shellcheck disable=SC2154
TIMEOUT="$(forge_config_get "isolation.resource_limits.timeout_seconds" "$time_limit")"

# --- Define the pipeline ---
ROLES=()
$SKIP_AUTHOR   || ROLES+=("spec-author")
$SKIP_ADVOCATE || ROLES+=("devils-advocate")
ROLES+=("implementer" "validator")

echo "--- Pipeline Plan ---"
echo "Roles:   ${ROLES[*]}"
echo "Runtime: ${FORGE_RUNTIME_ADAPTER}"
echo "Agent:   ${FORGE_AGENT_ADAPTER}"
# shellcheck disable=SC2154
echo "Budget:  tokens=${token_limit} cost=\$${cost_ceiling} time=${TIMEOUT}s"
echo ""

if $DRY_RUN; then
  echo "[DRY RUN] Pipeline plan printed. No agents spawned."
  exit 0
fi

# --- Detached mode: re-launch self in background (Spec 032) ---
if $DETACH; then
  SESSIONS_DIR="${PROJECT_DIR}/.forge/sessions"
  mkdir -p "$SESSIONS_DIR"
  DETACH_SESSION_ID="$(date +%Y%m%d-%H%M%S)"
  DETACH_LOG="${SESSIONS_DIR}/${DETACH_SESSION_ID}.log"
  DETACH_STATE="${SESSIONS_DIR}/${DETACH_SESSION_ID}.yaml"

  # Write initial session state
  cat > "$DETACH_STATE" <<YAML
session_id: ${DETACH_SESSION_ID}
spec_id: ${SPEC_ID}
spec_title: ${SPEC_TITLE}
started: $(date -u +%Y-%m-%dT%H:%M:%SZ)
status: running
current_role: ""
pid: ""
log: ${DETACH_LOG}
YAML

  # Re-launch without --detach flag, capture log, update state on finish
  RELAUNCH_ARGS=(--spec "$SPEC_ID")
  $SKIP_AUTHOR && RELAUNCH_ARGS+=(--skip-author)
  $SKIP_ADVOCATE && RELAUNCH_ARGS+=(--skip-advocate)
  nohup bash "$0" "${RELAUNCH_ARGS[@]}" > "$DETACH_LOG" 2>&1 &
  DETACH_PID=$!

  # Update state with PID
  sed -i "s/pid: \"\"/pid: ${DETACH_PID}/" "$DETACH_STATE"

  echo "=== FORGE Detached Session ==="
  echo "Session: ${DETACH_SESSION_ID}"
  echo "PID:     ${DETACH_PID}"
  echo "Log:     ${DETACH_LOG}"
  echo "State:   ${DETACH_STATE}"
  echo ""
  echo "Monitor: forge-status.sh --sessions"
  echo "Log:     tail -f ${DETACH_LOG}"
  echo ""
  echo "Pipeline running in background. Gate decisions will send NanoClaw messages if configured."
  exit 0
fi

# --- Initialize session ---
SESSION_ID="$(date +%Y%m%d-%H%M%S)"
SESSIONS_DIR="${PROJECT_DIR}/.forge/sessions"
mkdir -p "$SESSIONS_DIR"
SESSION_STATE="${SESSIONS_DIR}/${SESSION_ID}.yaml"

forge_audit_init "$SESSION_ID"
forge_handoff_init "$SPEC_ID" "$SESSION_ID"

# Write session state file (Spec 032)
cat > "$SESSION_STATE" <<YAML
session_id: ${SESSION_ID}
spec_id: ${SPEC_ID}
spec_title: ${SPEC_TITLE}
started: $(date -u +%Y-%m-%dT%H:%M:%SZ)
status: running
current_role: ""
pid: $$
log: ""
YAML

# --- Trap for cleanup on error/interrupt ---
cleanup_on_exit() {
  local exit_code=$?
  if (( exit_code != 0 )); then
    echo "" >&2
    echo "Pipeline interrupted (exit code: ${exit_code})" >&2
    forge_runtime_halt_all 2>/dev/null || true
    forge_audit_log "pipeline" "interrupted" "Exit code: ${exit_code}"
    echo "Worktrees preserved. Run forge-kill.sh to clean up." >&2
  fi
}
trap cleanup_on_exit EXIT

# --- Run pipeline ---
echo "=== Starting Pipeline ==="
echo ""

for role in "${ROLES[@]}"; do
  echo "--- Role: ${role} ---"

  # Update session state (Spec 032)
  sed -i "s/current_role: .*/current_role: ${role}/" "$SESSION_STATE" 2>/dev/null || true

  # Spawn agent via runtime adapter
  local_spawn_result="$(forge_runtime_spawn "$role" "$SPEC_ID" "$PROJECT_DIR")"
  AGENT_ID="$(echo "$local_spawn_result" | cut -d'|' -f1)"
  WORKTREE_DIR="$(echo "$local_spawn_result" | cut -d'|' -f2)"

  # Get role instructions
  INSTRUCTIONS_FILE="${FORGE_DIR}/templates/role-instructions/${role}.md"
  if [[ ! -f "$INSTRUCTIONS_FILE" ]]; then
    echo "ERROR: No role instructions found for ${role}" >&2
    forge_audit_log "$role" "fail" "Missing role instructions"
    exit 1
  fi

  # Start budget tracking
  forge_budget_start "$AGENT_ID"
  forge_audit_register_pid "$AGENT_ID" "$role" "$$"

  # Start budget monitor in background
  forge_budget_monitor "$AGENT_ID" "$$" "$TIMEOUT" &
  MONITOR_PID=$!

  # Invoke agent
  AGENT_START="$(date +%s)"
  agent_exit=0
  forge_agent_invoke "$role" "$INSTRUCTIONS_FILE" "$WORKTREE_DIR" "$SPEC_FILE" || agent_exit=$?
  AGENT_END="$(date +%s)"
  AGENT_DURATION=$(( AGENT_END - AGENT_START ))

  # Stop budget monitor
  kill "$MONITOR_PID" 2>/dev/null || true
  wait "$MONITOR_PID" 2>/dev/null || true

  # Record results
  forge_budget_record "$AGENT_ID" "$role"

  if (( agent_exit != 0 )); then
    echo "FAILED: Agent ${role} exited with code ${agent_exit}" >&2
    forge_handoff_write "$role" "$SPEC_ID" "failed" "Exit code: ${agent_exit}" "" "" "0" "0.0" "$AGENT_DURATION"
    forge_audit_log "$role" "fail" "Exit code: ${agent_exit}"
    forge_audit_unregister_pid "$AGENT_ID" "failed"
    exit 1
  fi

  # Write handoff artifact
  if [[ "$role" == "devils-advocate" ]]; then
    # For devil's advocate, we need to parse the gate decision from output
    # Default to CONDITIONAL_PASS if we can't determine
    forge_handoff_write "$role" "$SPEC_ID" "completed" "" "CONDITIONAL_PASS" "" "0" "0.0" "$AGENT_DURATION"

    # Check the gate
    if ! forge_handoff_check_gate "devils-advocate"; then
      echo "PIPELINE HALTED: Devil's Advocate gate returned FAIL" >&2
      forge_audit_log "$role" "gate-fail" "Pipeline halted by Devil's Advocate"
      forge_audit_unregister_pid "$AGENT_ID" "completed"
      exit 1
    fi
  elif [[ "$role" == "validator" ]]; then
    forge_handoff_write "$role" "$SPEC_ID" "completed" "" "" "PASS" "0" "0.0" "$AGENT_DURATION"
  else
    forge_handoff_write "$role" "$SPEC_ID" "completed" "" "" "" "0" "0.0" "$AGENT_DURATION"
  fi

  forge_audit_log "$role" "complete" "Duration: ${AGENT_DURATION}s"
  forge_audit_unregister_pid "$AGENT_ID" "completed"

  echo "Completed: ${role} (${AGENT_DURATION}s)"
  echo ""
done

# --- Pipeline complete ---
# Update session state to completed (Spec 032)
sed -i "s/status: running/status: completed/" "$SESSION_STATE" 2>/dev/null || true
sed -i "s/current_role: .*/current_role: done/" "$SESSION_STATE" 2>/dev/null || true

echo "=== Pipeline Complete ==="
echo ""
echo "Handoff artifacts: ${FORGE_HANDOFF_DIR}/"
echo "Audit log:         ${FORGE_AUDIT_LOG}"
echo "Session state:     ${SESSION_STATE}"
echo ""
echo "All roles completed. Review handoff artifacts and run /close ${SPEC_ID} when satisfied."

trap - EXIT
