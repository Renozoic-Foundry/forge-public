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

# --- Structured telemetry file (Spec 152) ---
TELEMETRY_DIR="${PROJECT_DIR}/.forge/audit"
mkdir -p "$TELEMETRY_DIR"
TELEMETRY_FILE="${TELEMETRY_DIR}/${SPEC_ID}-pipeline.jsonl"

# --- Idempotency check (Spec 152) ---
# Returns 0 (true = skip) if a completed handoff artifact exists for this role
forge_role_already_complete() {
  local role="$1"
  local spec_id="$2"
  local handoff_base="${PROJECT_DIR}/.forge/handoffs/spec-${spec_id}"
  if [[ ! -d "$handoff_base" ]]; then
    return 1
  fi
  for session_dir in "${handoff_base}"/*/; do
    [[ -d "$session_dir" ]] || continue
    local artifact="${session_dir}${role}.json"
    if [[ -f "$artifact" ]]; then
      if grep -q '"status":"completed"' "$artifact" 2>/dev/null; then
        return 0
      fi
    fi
  done
  return 1
}

# --- Telemetry emit (Spec 152) ---
forge_telemetry_emit() {
  local role="$1"
  local spec_id="$2"
  local start_time="$3"
  local end_time="$4"
  local exit_code="$5"
  local duration="$6"
  local status="$7"
  local artifact_path="${8:-}"
  local skipped="${9:-false}"

  local record="{"
  record+="\"role\":\"${role}\","
  record+="\"spec_id\":\"${spec_id}\","
  record+="\"start_time\":\"${start_time}\","
  record+="\"end_time\":\"${end_time}\","
  record+="\"exit_code\":${exit_code},"
  record+="\"duration_seconds\":${duration},"
  record+="\"status\":\"${status}\","
  record+="\"artifact_path\":\"${artifact_path}\","
  record+="\"skipped\":${skipped}"
  record+="}"

  echo "$record" >> "$TELEMETRY_FILE"
}

# --- Circuit breaker: structured failure record (Spec 152) ---
forge_write_failure_record() {
  local spec_id="$1"
  local role="$2"
  local exit_code="$3"
  local error_summary="$4"
  local classification="$5"

  local timestamp
  timestamp="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  local record="{"
  record+="\"spec_id\":\"${spec_id}\","
  record+="\"role\":\"${role}\","
  record+="\"exit_code\":${exit_code},"
  record+="\"timestamp\":\"${timestamp}\","
  record+="\"error_summary\":\"${error_summary}\","
  record+="\"classification\":\"${classification}\""
  record+="}"

  echo "$record" >> "${TELEMETRY_DIR}/${spec_id}-failures.jsonl"
}

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

  # --- Idempotency guard (Spec 152) ---
  if forge_role_already_complete "$role" "$SPEC_ID"; then
    echo "Role already complete, skipping: ${role}"
    forge_audit_log "$role" "skip" "Completed handoff artifact found — idempotency guard"
    SKIP_TS="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    forge_telemetry_emit "$role" "$SPEC_ID" "$SKIP_TS" "$SKIP_TS" 0 0 "skipped" "" "true"
    echo ""
    continue
  fi

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

  # Invoke agent — with circuit breaker (Spec 152)
  AGENT_START="$(date +%s)"
  AGENT_START_ISO="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  agent_exit=0
  forge_agent_invoke "$role" "$INSTRUCTIONS_FILE" "$WORKTREE_DIR" "$SPEC_FILE" || agent_exit=$?
  AGENT_END="$(date +%s)"
  AGENT_DURATION=$(( AGENT_END - AGENT_START ))

  # --- Circuit breaker (Spec 152) ---
  if (( agent_exit != 0 )); then
    if (( agent_exit == 1 )); then
      # Transient failure — retry once with 5s backoff
      echo "TRANSIENT FAILURE: ${role} exited with code ${agent_exit}, retrying in 5s..." >&2
      forge_audit_log "$role" "transient-fail" "Exit code: ${agent_exit} — retrying"
      forge_write_failure_record "$SPEC_ID" "$role" "$agent_exit" "Transient failure, retrying" "transient"
      sleep 5
      agent_exit=0
      AGENT_START="$(date +%s)"
      AGENT_START_ISO="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
      forge_agent_invoke "$role" "$INSTRUCTIONS_FILE" "$WORKTREE_DIR" "$SPEC_FILE" || agent_exit=$?
      AGENT_END="$(date +%s)"
      AGENT_DURATION=$(( AGENT_END - AGENT_START ))
    fi

    if (( agent_exit != 0 )); then
      # Permanent failure — halt pipeline
      FAILURE_CLASS="permanent"
      if (( agent_exit == 1 )); then
        FAILURE_CLASS="transient-exhausted"
      fi
      echo "PERMANENT FAILURE: ${role} exited with code ${agent_exit} — pipeline halted" >&2
      forge_write_failure_record "$SPEC_ID" "$role" "$agent_exit" "Pipeline halted" "$FAILURE_CLASS"

      # Stop budget monitor
      kill "$MONITOR_PID" 2>/dev/null || true
      wait "$MONITOR_PID" 2>/dev/null || true
      forge_budget_record "$AGENT_ID" "$role"

      AGENT_END_ISO="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
      forge_telemetry_emit "$role" "$SPEC_ID" "$AGENT_START_ISO" "$AGENT_END_ISO" "$agent_exit" "$AGENT_DURATION" "failed" "" "false"
      forge_handoff_write "$role" "$SPEC_ID" "failed" "Exit code: ${agent_exit}" "" "" "0" "0.0" "$AGENT_DURATION"
      forge_audit_log "$role" "fail" "Exit code: ${agent_exit} (${FAILURE_CLASS})"
      forge_audit_unregister_pid "$AGENT_ID" "failed"
      exit 1
    fi
  fi

  # Stop budget monitor
  kill "$MONITOR_PID" 2>/dev/null || true
  wait "$MONITOR_PID" 2>/dev/null || true

  # Record results
  forge_budget_record "$AGENT_ID" "$role"

  # Write handoff artifact
  if [[ "$role" == "devils-advocate" ]]; then
    forge_handoff_write "$role" "$SPEC_ID" "completed" "" "CONDITIONAL_PASS" "" "0" "0.0" "$AGENT_DURATION"

    # Check the gate
    if ! forge_handoff_check_gate "devils-advocate"; then
      echo "PIPELINE HALTED: Devil's Advocate gate returned FAIL" >&2
      forge_audit_log "$role" "gate-fail" "Pipeline halted by Devil's Advocate"
      forge_audit_unregister_pid "$AGENT_ID" "completed"
      AGENT_END_ISO="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
      forge_telemetry_emit "$role" "$SPEC_ID" "$AGENT_START_ISO" "$AGENT_END_ISO" 0 "$AGENT_DURATION" "gate-fail" "" "false"
      exit 1
    fi
  elif [[ "$role" == "validator" ]]; then
    forge_handoff_write "$role" "$SPEC_ID" "completed" "" "" "PASS" "0" "0.0" "$AGENT_DURATION"
  else
    forge_handoff_write "$role" "$SPEC_ID" "completed" "" "" "" "0" "0.0" "$AGENT_DURATION"
  fi

  # Emit structured telemetry (Spec 152)
  AGENT_END_ISO="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  ARTIFACT_PATH="${FORGE_HANDOFF_DIR}/${role}.json"
  forge_telemetry_emit "$role" "$SPEC_ID" "$AGENT_START_ISO" "$AGENT_END_ISO" 0 "$AGENT_DURATION" "completed" "$ARTIFACT_PATH" "false"

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
