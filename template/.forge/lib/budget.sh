#!/usr/bin/env bash
# FORGE budget.sh — Budget tracking and enforcement
# Sourced by other FORGE scripts. Do not execute directly.

declare -gA FORGE_BUDGET_START_TIMES

forge_budget_start() {
  local agent_id="$1"
  FORGE_BUDGET_START_TIMES["$agent_id"]="$(date +%s)"
}

forge_budget_check_time() {
  local agent_id="$1"
  local timeout_seconds="$2"

  local start="${FORGE_BUDGET_START_TIMES[$agent_id]}"
  if [[ -z "$start" ]]; then
    echo "WARN: No start time recorded for agent ${agent_id}" >&2
    return 1
  fi

  local now
  now="$(date +%s)"
  local elapsed=$(( now - start ))

  if (( elapsed >= timeout_seconds )); then
    echo "BUDGET BREACH: Agent ${agent_id} exceeded time limit (${elapsed}s >= ${timeout_seconds}s)" >&2
    return 1
  fi

  return 0
}

forge_budget_elapsed() {
  local agent_id="$1"

  local start="${FORGE_BUDGET_START_TIMES[$agent_id]}"
  if [[ -z "$start" ]]; then
    echo "0"
    return
  fi

  local now
  now="$(date +%s)"
  echo $(( now - start ))
}

forge_budget_record() {
  local agent_id="$1"
  local role="$2"
  local token_usage="${3:-0}"
  local cost_usd="${4:-0.0}"

  local elapsed
  elapsed="$(forge_budget_elapsed "$agent_id")"

  forge_audit_log "$role" "budget-record" "elapsed=${elapsed}s tokens=${token_usage} cost=\$${cost_usd}"
}

forge_budget_monitor() {
  local agent_id="$1"
  local pid="$2"
  local timeout_seconds="$3"
  local check_interval="${4:-10}"

  while kill -0 "$pid" 2>/dev/null; do
    if ! forge_budget_check_time "$agent_id" "$timeout_seconds" 2>/dev/null; then
      echo "BUDGET BREACH: Halting agent ${agent_id} (PID ${pid})" >&2
      kill -TERM "$pid" 2>/dev/null
      forge_audit_log "${agent_id}" "budget-breach" "Time limit exceeded — agent halted"
      return 1
    fi
    sleep "$check_interval"
  done
}
