#!/usr/bin/env bash
# FORGE Status — query running agents and recent activity
# Usage: forge-status.sh [agent-id]
set -euo pipefail

FORGE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_DIR="$(cd "${FORGE_DIR}/.." && pwd)"

source "${FORGE_DIR}/lib/config.sh"
source "${FORGE_DIR}/lib/audit.sh"
source "${FORGE_DIR}/lib/gate-state.sh"
source "${FORGE_DIR}/lib/logging.sh"

forge_log_init "forge-status"

AGENT_ID=""
SHOW_SESSIONS=false
PIPELINE_SPEC=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --sessions) SHOW_SESSIONS=true; shift ;;
    --pipeline) PIPELINE_SPEC="$2"; shift 2 ;;
    -h|--help)
      echo "Usage: forge-status.sh [agent-id] [--sessions] [--pipeline SPEC-ID]"
      echo "  (no args)           Show most recent session status"
      echo "  agent-id            Show detailed status for a specific agent"
      echo "  --sessions          List all sessions (active, paused, completed) — Spec 032"
      echo "  --pipeline SPEC-ID  Show per-role pipeline status from telemetry — Spec 152"
      exit 0 ;;
    *) AGENT_ID="$1"; shift ;;
  esac
done

# --- Session listing mode (Spec 032) ---
if $SHOW_SESSIONS; then
  SESSIONS_DIR="${PROJECT_DIR}/.forge/sessions"
  echo "=== FORGE Sessions ==="
  if [[ ! -d "$SESSIONS_DIR" ]] || [[ -z "$(ls -A "$SESSIONS_DIR" 2>/dev/null)" ]]; then
    echo "No sessions found in ${SESSIONS_DIR}"
    exit 0
  fi
  printf "%-22s %-6s %-12s %-14s %s\n" "SESSION" "SPEC" "STATUS" "ROLE" "STARTED"
  printf "%-22s %-6s %-12s %-14s %s\n" "-------" "----" "------" "----" "-------"
  for state_file in "${SESSIONS_DIR}"/*.yaml; do
    [[ -f "$state_file" ]] || continue
    local_session="$(grep '^session_id:' "$state_file" | awk '{print $2}')"
    local_spec="$(grep '^spec_id:' "$state_file" | awk '{print $2}')"
    local_status="$(grep '^status:' "$state_file" | awk '{print $2}')"
    local_role="$(grep '^current_role:' "$state_file" | awk '{print $2}')"
    local_started="$(grep '^started:' "$state_file" | awk '{print $2}')"
    local_pid="$(grep '^pid:' "$state_file" | awk '{print $2}' | tr -d '"')"
    # Check if process still alive
    if [[ "$local_status" == "running" ]] && [[ -n "$local_pid" ]]; then
      if ! kill -0 "$local_pid" 2>/dev/null; then
        local_status="dead(crashed?)"
      fi
    fi
    printf "%-22s %-6s %-12s %-14s %s\n" "$local_session" "$local_spec" "$local_status" "$local_role" "$local_started"
  done
  echo ""
  echo "Resume: forge-orchestrate.sh --spec NNN (re-run from scratch)"
  echo "Log:    tail -f .forge/sessions/<session>.log"
  exit 0
fi

# --- Pipeline telemetry mode (Spec 152) ---
if [[ -n "$PIPELINE_SPEC" ]]; then
  TELEMETRY_FILE="${PROJECT_DIR}/.forge/audit/${PIPELINE_SPEC}-pipeline.jsonl"
  FAILURE_FILE="${PROJECT_DIR}/.forge/audit/${PIPELINE_SPEC}-failures.jsonl"

  echo "=== FORGE Pipeline Status — Spec ${PIPELINE_SPEC} ==="
  echo ""

  if [[ ! -f "$TELEMETRY_FILE" ]]; then
    echo "No telemetry found for spec ${PIPELINE_SPEC}."
    echo "Expected: ${TELEMETRY_FILE}"
    exit 0
  fi

  printf "%-20s %-12s %-6s %-10s %-26s %-26s\n" "ROLE" "STATUS" "EXIT" "DURATION" "START" "END"
  printf "%-20s %-12s %-6s %-10s %-26s %-26s\n" "----" "------" "----" "--------" "-----" "---"
  while IFS= read -r line; do
    p_role="$(echo "$line" | grep -o '"role":"[^"]*"' | cut -d'"' -f4)"
    p_status="$(echo "$line" | grep -o '"status":"[^"]*"' | cut -d'"' -f4)"
    p_exit="$(echo "$line" | grep -o '"exit_code":[0-9]*' | cut -d: -f2)"
    p_dur="$(echo "$line" | grep -o '"duration_seconds":[0-9]*' | cut -d: -f2)"
    p_start="$(echo "$line" | grep -o '"start_time":"[^"]*"' | cut -d'"' -f4)"
    p_end="$(echo "$line" | grep -o '"end_time":"[^"]*"' | cut -d'"' -f4)"
    printf "%-20s %-12s %-6s %-10s %-26s %-26s\n" "$p_role" "$p_status" "$p_exit" "${p_dur}s" "$p_start" "$p_end"
  done < "$TELEMETRY_FILE"

  # Show any failure records
  if [[ -f "$FAILURE_FILE" ]]; then
    echo ""
    echo "--- Failure Records ---"
    while IFS= read -r line; do
      f_role="$(echo "$line" | grep -o '"role":"[^"]*"' | cut -d'"' -f4)"
      f_exit="$(echo "$line" | grep -o '"exit_code":[0-9]*' | cut -d: -f2)"
      f_class="$(echo "$line" | grep -o '"classification":"[^"]*"' | cut -d'"' -f4)"
      f_summary="$(echo "$line" | grep -o '"error_summary":"[^"]*"' | cut -d'"' -f4)"
      f_ts="$(echo "$line" | grep -o '"timestamp":"[^"]*"' | cut -d'"' -f4)"
      echo "  ${f_ts} [${f_role}] exit=${f_exit} class=${f_class}: ${f_summary}"
    done < "$FAILURE_FILE"
  fi

  echo ""
  echo "Telemetry: ${TELEMETRY_FILE}"
  exit 0
fi

# Find the most recent audit session
LATEST_AUDIT=""
if [[ -d "${PROJECT_DIR}/.forge/audit" ]]; then
  LATEST_AUDIT="$(ls -1d "${PROJECT_DIR}/.forge/audit/"*/ 2>/dev/null | sort -r | head -1)"
fi

if [[ -z "$LATEST_AUDIT" ]]; then
  echo "No FORGE sessions found."
  exit 0
fi

FORGE_AUDIT_DIR="$LATEST_AUDIT"
FORGE_AUDIT_LOG="${FORGE_AUDIT_DIR}pipeline.log"
FORGE_PID_FILE="${FORGE_AUDIT_DIR}pids.json"

SESSION_NAME="$(basename "$LATEST_AUDIT")"
echo "=== FORGE Status ==="
echo "Session: ${SESSION_NAME}"
echo ""

if [[ -n "$AGENT_ID" ]]; then
  # Detailed status for a specific agent
  echo "Agent: ${AGENT_ID}"

  if [[ -f "$FORGE_PID_FILE" ]]; then
    local_entry="$(grep "$AGENT_ID" "$FORGE_PID_FILE" 2>/dev/null || echo "")"
    if [[ -n "$local_entry" ]]; then
      local_pid="$(echo "$local_entry" | grep -o '"pid":[0-9]*' | cut -d: -f2)"
      local_role="$(echo "$local_entry" | grep -o '"role":"[^"]*"' | cut -d'"' -f4)"
      local_status="$(echo "$local_entry" | grep -o '"status":"[^"]*"' | cut -d'"' -f4)"
      local_started="$(echo "$local_entry" | grep -o '"started":"[^"]*"' | cut -d'"' -f4)"

      echo "Role:    ${local_role}"
      echo "PID:     ${local_pid}"
      echo "Status:  ${local_status}"
      echo "Started: ${local_started}"

      # Check if process is actually running
      if [[ -n "$local_pid" ]] && kill -0 "$local_pid" 2>/dev/null; then
        echo "Process: alive"
      else
        echo "Process: not running"
      fi
    else
      echo "Agent not found in current session."
    fi
  fi

  # Show relevant audit log entries
  echo ""
  echo "--- Audit Log (${AGENT_ID}) ---"
  grep "$AGENT_ID" "$FORGE_AUDIT_LOG" 2>/dev/null || echo "(no entries)"

else
  # Summary table of all agents
  if [[ ! -f "$FORGE_PID_FILE" || "$(cat "$FORGE_PID_FILE")" == "[]" ]]; then
    echo "No agents registered in current session."
  else
    printf "%-30s %-20s %-10s %-10s\n" "Agent ID" "Role" "Status" "PID"
    printf "%-30s %-20s %-10s %-10s\n" "--------" "----" "------" "---"

    # Parse each agent entry from the PID file
    grep -o '"agent_id":"[^"]*"' "$FORGE_PID_FILE" | cut -d'"' -f4 | while read -r aid; do
      local_entry="$(grep "$aid" "$FORGE_PID_FILE")"
      local_role="$(echo "$local_entry" | grep -o '"role":"[^"]*"' | head -1 | cut -d'"' -f4)"
      local_status="$(echo "$local_entry" | grep -o '"status":"[^"]*"' | head -1 | cut -d'"' -f4)"
      local_pid="$(echo "$local_entry" | grep -o '"pid":[0-9]*' | head -1 | cut -d: -f2)"
      printf "%-30s %-20s %-10s %-10s\n" "$aid" "$local_role" "$local_status" "$local_pid"
    done
  fi

  echo ""
  echo "--- Recent Audit Log ---"
  tail -10 "$FORGE_AUDIT_LOG" 2>/dev/null || echo "(no entries)"
fi

# Gate state summary
forge_gate_state_init "$PROJECT_DIR"
echo ""
echo "--- Gate State ---"
forge_gate_state_list_specs

echo ""
echo "Full audit log: ${FORGE_AUDIT_LOG}"
