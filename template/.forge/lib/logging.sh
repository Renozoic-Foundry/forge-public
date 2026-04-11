#!/usr/bin/env bash
# FORGE logging.sh — structured logging library for all FORGE scripts
# Source this file; do not execute directly.
#
# Usage:
#   source "${FORGE_DIR}/lib/logging.sh"
#   forge_log_init "my-script"
#   forge_log_step "setup"
#   forge_log_info "Starting installation"
#   forge_log_debug "Checking path: ${some_path}"
#   forge_log_warn "Tool not found, will install"
#   forge_log_error "Installation failed"
#
# Environment:
#   FORGE_LOG_LEVEL — console verbosity: DEBUG, INFO (default), WARN, ERROR
#   FORGE_LOG_DIR   — override log directory (default: .forge/logs)
#
# Log files always capture all levels regardless of FORGE_LOG_LEVEL.

# Guard against double-sourcing
if [[ -n "${_FORGE_LOGGING_LOADED:-}" ]]; then return 0; fi
_FORGE_LOGGING_LOADED=1

# --- Internal state ---
_FORGE_LOG_SCRIPT=""
_FORGE_LOG_STEP=""
_FORGE_LOG_FILE=""
_FORGE_LOG_DIR=""
_FORGE_LOG_MAX_SIZE=102400  # 100KB — rotate when exceeded
_FORGE_LOG_KEEP=5           # keep .log.1 through .log.5

# --- Colors (console only, if terminal supports them) ---
_FORGE_LOG_RED=""
_FORGE_LOG_GREEN=""
_FORGE_LOG_YELLOW=""
_FORGE_LOG_CYAN=""
_FORGE_LOG_BOLD=""
_FORGE_LOG_RESET=""
if [[ -t 2 ]]; then
  _FORGE_LOG_RED="\033[0;31m"
  _FORGE_LOG_GREEN="\033[0;32m"
  _FORGE_LOG_YELLOW="\033[1;33m"
  _FORGE_LOG_CYAN="\033[0;36m"
  _FORGE_LOG_BOLD="\033[1m"
  _FORGE_LOG_RESET="\033[0m"
fi

# --- Level ordering ---
_forge_log_level_num() {
  case "${1:-INFO}" in
    DEBUG) echo 0 ;;
    INFO)  echo 1 ;;
    WARN)  echo 2 ;;
    ERROR) echo 3 ;;
    *)     echo 1 ;;
  esac
}

# --- Log rotation ---
_forge_log_rotate() {
  local logfile="$1"
  if [[ ! -f "$logfile" ]]; then return 0; fi

  local size
  size="$(wc -c < "$logfile" 2>/dev/null || echo 0)"
  if (( size < _FORGE_LOG_MAX_SIZE )); then return 0; fi

  # Rotate: .log.5 → deleted, .log.4 → .log.5, ... .log → .log.1
  local i=$_FORGE_LOG_KEEP
  while (( i > 1 )); do
    local prev=$(( i - 1 ))
    if [[ -f "${logfile}.${prev}" ]]; then
      mv "${logfile}.${prev}" "${logfile}.${i}"
    fi
    i=$prev
  done
  mv "$logfile" "${logfile}.1"
}

# --- Initialize logging for a script ---
forge_log_init() {
  _FORGE_LOG_SCRIPT="${1:?forge_log_init requires a script name}"
  _FORGE_LOG_STEP=""

  # Determine log directory
  if [[ -n "${FORGE_LOG_DIR:-}" ]]; then
    _FORGE_LOG_DIR="$FORGE_LOG_DIR"
  elif [[ -n "${PROJECT_DIR:-}" ]]; then
    _FORGE_LOG_DIR="${PROJECT_DIR}/.forge/logs"
  elif [[ -n "${FORGE_DIR:-}" ]]; then
    _FORGE_LOG_DIR="${FORGE_DIR}/../.forge/logs"
  else
    _FORGE_LOG_DIR=".forge/logs"
  fi

  mkdir -p "$_FORGE_LOG_DIR"
  _FORGE_LOG_FILE="${_FORGE_LOG_DIR}/${_FORGE_LOG_SCRIPT}.log"

  # Rotate if over size limit
  _forge_log_rotate "$_FORGE_LOG_FILE"

  # Session separator
  {
    echo ""
    echo "=== ${_FORGE_LOG_SCRIPT} — $(date '+%Y-%m-%d %H:%M:%S') ==="
  } >> "$_FORGE_LOG_FILE"
}

# --- Set step context ---
forge_log_step() {
  _FORGE_LOG_STEP="${1:-}"
  _forge_log_write "INFO" "--- ${_FORGE_LOG_STEP} ---"
  printf '%b%b=== %s ===%b\n' "${_FORGE_LOG_BOLD}" "${_FORGE_LOG_CYAN}" "$_FORGE_LOG_STEP" "${_FORGE_LOG_RESET}" >&2
}

# --- Core log function ---
_forge_log_write() {
  local level="$1"
  local message="$2"
  local timestamp
  timestamp="$(date '+%Y-%m-%d %H:%M:%S')"

  local step_part=""
  if [[ -n "$_FORGE_LOG_STEP" ]]; then
    step_part="$_FORGE_LOG_STEP"
  else
    step_part="-"
  fi

  # Always write to file (all levels)
  if [[ -n "$_FORGE_LOG_FILE" ]]; then
    printf '%s | %-5s | %s | %s | %s\n' \
      "$timestamp" "$level" "$_FORGE_LOG_SCRIPT" "$step_part" "$message" \
      >> "$_FORGE_LOG_FILE"
  fi

  # Console output respects FORGE_LOG_LEVEL
  local console_threshold
  console_threshold="$(_forge_log_level_num "${FORGE_LOG_LEVEL:-INFO}")"
  local msg_level
  msg_level="$(_forge_log_level_num "$level")"

  if (( msg_level >= console_threshold )); then
    local color=""
    local prefix=""
    case "$level" in
      DEBUG) color="$_FORGE_LOG_CYAN";   prefix="[.]" ;;
      INFO)  color="$_FORGE_LOG_GREEN";  prefix="[✓]" ;;
      WARN)  color="$_FORGE_LOG_YELLOW"; prefix="[!]" ;;
      ERROR) color="$_FORGE_LOG_RED";    prefix="[✗]" ;;
    esac
    printf '%b%s%b %s\n' "$color" "$prefix" "$_FORGE_LOG_RESET" "$message" >&2
  fi
}

# --- Public log functions ---
forge_log_debug() { _forge_log_write "DEBUG" "$1"; }
forge_log_info()  { _forge_log_write "INFO"  "$1"; }
forge_log_warn()  { _forge_log_write "WARN"  "$1"; }
forge_log_error() { _forge_log_write "ERROR" "$1"; }
