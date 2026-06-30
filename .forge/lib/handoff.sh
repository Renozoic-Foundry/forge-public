#!/usr/bin/env bash
# FORGE handoff.sh — Handoff artifact read/write utilities
# Sourced by other FORGE scripts. Do not execute directly.

FORGE_HANDOFF_DIR=""

forge_handoff_init() {
  local spec_id="$1"
  local session_id="$2"
  FORGE_HANDOFF_DIR="${PROJECT_DIR}/.forge/handoffs/spec-${spec_id}/${session_id}"
  mkdir -p "$FORGE_HANDOFF_DIR"
  echo "Handoff directory: ${FORGE_HANDOFF_DIR}" >&2
}

forge_handoff_write() {
  local role="$1"
  local spec_id="$2"
  local status="$3"
  local notes="${4:-}"
  local gate_decision="${5:-}"
  local validation_result="${6:-}"
  local token_usage="${7:-0}"
  local cost_usd="${8:-0.0}"
  local duration_seconds="${9:-0}"

  if [[ -z "$FORGE_HANDOFF_DIR" ]]; then
    echo "ERROR: Handoff not initialized — call forge_handoff_init first" >&2
    return 1
  fi

  local timestamp
  timestamp="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  local artifact_file="${FORGE_HANDOFF_DIR}/${role}.json"

  local json="{"
  json+="\"role\":\"${role}\","
  json+="\"spec_id\":\"${spec_id}\","
  json+="\"timestamp\":\"${timestamp}\","
  json+="\"status\":\"${status}\","
  json+="\"token_usage\":${token_usage},"
  json+="\"cost_usd\":${cost_usd},"
  json+="\"duration_seconds\":${duration_seconds},"
  json+="\"notes\":\"${notes}\""

  if [[ -n "$gate_decision" ]]; then
    json+=",\"gate_decision\":\"${gate_decision}\""
  fi
  if [[ -n "$validation_result" ]]; then
    json+=",\"validation_result\":\"${validation_result}\""
  fi

  json+="}"

  echo "$json" > "$artifact_file"
  echo "Handoff artifact written: ${artifact_file}" >&2
}

forge_handoff_read() {
  local role="$1"

  if [[ -z "$FORGE_HANDOFF_DIR" ]]; then
    echo "ERROR: Handoff not initialized" >&2
    return 1
  fi

  local artifact_file="${FORGE_HANDOFF_DIR}/${role}.json"
  if [[ ! -f "$artifact_file" ]]; then
    echo "ERROR: No handoff artifact for role '${role}'" >&2
    return 1
  fi

  cat "$artifact_file"
}

forge_handoff_check_gate() {
  local role="${1:-devils-advocate}"

  local artifact
  artifact="$(forge_handoff_read "$role" 2>/dev/null)" || return 1

  local decision
  decision="$(echo "$artifact" | grep -o '"gate_decision":"[^"]*"' | cut -d'"' -f4)"

  case "$decision" in
    PASS)
      echo "Gate PASSED — proceeding to next role" >&2
      return 0
      ;;
    CONDITIONAL_PASS)
      echo "Gate CONDITIONAL PASS — proceeding with noted conditions" >&2
      return 0
      ;;
    FAIL)
      echo "Gate FAILED — pipeline halted" >&2
      return 1
      ;;
    *)
      echo "ERROR: Unknown or missing gate decision: '${decision}'" >&2
      return 1
      ;;
  esac
}
