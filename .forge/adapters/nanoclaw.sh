#!/usr/bin/env bash
# FORGE nanoclaw.sh — NanoClaw messaging adapter (thin wrapper)
# Delegates gate delivery to the nanoclaw-forge bridge CLI (ncforge) when
# available. Falls back to legacy inline adapter if bridge is not installed.
#
# The bridge package (nanoclaw-forge) handles:
#   - Gate message formatting and IPC transport
#   - Gate response parsing (approve/reject/query/defer)
#   - Batch validation checkpoints, gate-meta sidecar management
#
# FORGE handles (this file + orchestrator):
#   - When to send gates, what evidence to include, what to do with the answer
#
# See: ADR-nanoclaw-forge-extraction.md
# Depends-on: Spec 074 (bridge extraction), Spec 064 (PAL extraction)

NANOCLAW_ENABLED=false

forge_nanoclaw_init() {
  source "${1}/.forge/lib/gate-state.sh"
  forge_gate_state_init "$1"
  NANOCLAW_ENABLED="${FORGE_NANOCLAW_ENABLED:-false}"
}

forge_nanoclaw_is_enabled() { [[ "$NANOCLAW_ENABLED" == "true" ]]; }
_nanoclaw_has_bridge() { command -v ncforge &>/dev/null; }

_nanoclaw_try_legacy() {
  local fn="$1"; shift
  if type "$fn" &>/dev/null 2>&1; then
    echo "DEPRECATION: Using legacy inline adapter. Install nanoclaw-forge bridge." >&2
    "$fn" "$@"; return $?
  fi
  echo "WARNING: ncforge not installed. Install: pip install nanoclaw-forge" >&2
  return 1
}

forge_nanoclaw_send() {
  forge_nanoclaw_is_enabled || { echo "ERROR: NanoClaw not enabled." >&2; return 1; }
  if _nanoclaw_has_bridge; then
    ncforge gate send --spec "$1" --type "$2" --evidence "${3:-"{}"}" --json
  else _nanoclaw_try_legacy forge_nanoclaw_send_gate "$1" "$2" "${3:-"{}"}"; fi
}

forge_nanoclaw_poll() {
  if _nanoclaw_has_bridge; then
    ncforge gate poll --gate-id "$2" --nonce "$3" --json
  else _nanoclaw_try_legacy forge_nanoclaw_poll_response "$1" "$2" "$3"; fi
}

forge_nanoclaw_gate_flow() {
  forge_nanoclaw_is_enabled || { echo "ERROR: NanoClaw not enabled." >&2; return 1; }
  if _nanoclaw_has_bridge; then
    local result; result="$(ncforge gate flow --spec "$1" --type "$2" --evidence "${3:-"{}"}" --json)"; local rc=$?
    case "$result" in
      approve) forge_gate_state_record "$1" "gate-approved" "PASS" "Approved via NanoClaw bridge" "" "/implement" ;;
      reject)  forge_gate_state_record "$1" "gate-rejected" "FAIL" "Rejected via NanoClaw bridge" "" "/implement" ;;
    esac
    echo "$result"; return $rc
  fi
  _nanoclaw_try_legacy _legacy_nanoclaw_gate_flow "$1" "$2" "${3:-"{}"}"
}

forge_nanoclaw_status() {
  if ! forge_nanoclaw_is_enabled; then echo "NanoClaw: DISABLED"; return; fi
  echo "NanoClaw: ENABLED"
  if _nanoclaw_has_bridge; then echo "Bridge: ncforge $(ncforge version 2>/dev/null || echo unknown)"
  else echo "Bridge: NOT INSTALLED (pip install nanoclaw-forge)"; fi
}
