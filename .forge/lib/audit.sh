#!/usr/bin/env bash
# FORGE audit.sh — Audit logging utilities
# Sourced by other FORGE scripts. Do not execute directly.

FORGE_AUDIT_DIR=""
FORGE_AUDIT_LOG=""
FORGE_PID_FILE=""

forge_audit_init() {
  local session_id="$1"
  FORGE_AUDIT_DIR="${PROJECT_DIR}/.forge/audit/${session_id}"
  FORGE_AUDIT_LOG="${FORGE_AUDIT_DIR}/pipeline.log"
  FORGE_PID_FILE="${FORGE_AUDIT_DIR}/pids.json"
  mkdir -p "$FORGE_AUDIT_DIR"

  echo "[]" > "$FORGE_PID_FILE"
  forge_audit_log "pipeline" "init" "Session ${session_id} started"
  echo "Audit directory: ${FORGE_AUDIT_DIR}" >&2
}

forge_audit_log() {
  local role="$1"
  local event="$2"
  local message="${3:-}"

  if [[ -z "$FORGE_AUDIT_LOG" ]]; then
    echo "ERROR: Audit not initialized — call forge_audit_init first" >&2
    return 1
  fi

  local timestamp
  timestamp="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  echo "${timestamp} [${role}] ${event}: ${message}" >> "$FORGE_AUDIT_LOG"
}

forge_audit_register_pid() {
  local agent_id="$1"
  local role="$2"
  local pid="$3"

  if [[ -z "$FORGE_PID_FILE" ]]; then
    echo "ERROR: Audit not initialized" >&2
    return 1
  fi

  local timestamp
  timestamp="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  local entry="{\"agent_id\":\"${agent_id}\",\"role\":\"${role}\",\"pid\":${pid},\"started\":\"${timestamp}\",\"status\":\"running\"}"

  local existing=""
  if [[ -f "$FORGE_PID_FILE" ]]; then
    existing="$(cat "$FORGE_PID_FILE")"
  fi

  if [[ "$existing" == "[]" || -z "$existing" ]]; then
    echo "[${entry}]" > "$FORGE_PID_FILE"
  else
    existing="${existing%]}"
    echo "${existing},${entry}]" > "$FORGE_PID_FILE"
  fi

  forge_audit_log "$role" "spawn" "PID=${pid} agent_id=${agent_id}"
}

forge_audit_unregister_pid() {
  local agent_id="$1"
  local final_status="${2:-halted}"

  if [[ -z "$FORGE_PID_FILE" || ! -f "$FORGE_PID_FILE" ]]; then
    return 0
  fi

  local tmp_file="${FORGE_PID_FILE}.tmp"
  sed "s/\"agent_id\":\"${agent_id}\",\(.*\)\"status\":\"running\"/\"agent_id\":\"${agent_id}\",\1\"status\":\"${final_status}\"/" \
    "$FORGE_PID_FILE" > "$tmp_file"
  mv "$tmp_file" "$FORGE_PID_FILE"
}

forge_audit_get_pids() {
  if [[ -z "$FORGE_PID_FILE" || ! -f "$FORGE_PID_FILE" ]]; then
    echo "[]"
    return
  fi
  cat "$FORGE_PID_FILE"
}

forge_audit_get_running_pids() {
  if [[ -z "$FORGE_PID_FILE" || ! -f "$FORGE_PID_FILE" ]]; then
    return
  fi
  grep -o '"pid":[0-9]*' "$FORGE_PID_FILE" | cut -d: -f2
}
