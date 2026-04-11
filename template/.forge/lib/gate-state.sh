#!/usr/bin/env bash
# FORGE gate-state.sh — Persistent gate outcome tracking
# Sourced by other FORGE scripts. Do not execute directly.
#
# Gate outcomes are written to .forge/gates/<spec-id>.json as they occur.
# Chain decision logic reads from these files instead of conversation context.
# Full audit trail: all gate outcomes are appended, not overwritten.
#
# Dependencies: jq

FORGE_GATES_DIR=""

# --- Initialization ---

forge_gate_state_init() {
  local project_dir="$1"
  FORGE_GATES_DIR="${project_dir}/.forge/gates"
  mkdir -p "$FORGE_GATES_DIR"
}

# --- Write Gate Outcome ---

forge_gate_state_record() {
  # Record a gate outcome to persistent storage.
  # Usage: forge_gate_state_record <spec_id> <gate_name> <status> <reason> [session_id] [command] [challenge_nonce]
  local spec_id="$1"
  local gate_name="$2"
  local status="$3"
  local reason="${4:-}"
  local session_id="${5:-}"
  local command="${6:-}"
  local challenge_nonce="${7:-}"

  if [[ -z "$FORGE_GATES_DIR" ]]; then
    echo "ERROR: Gate state not initialized — call forge_gate_state_init first" >&2
    return 1
  fi

  local gate_file="${FORGE_GATES_DIR}/${spec_id}.json"
  local timestamp
  timestamp="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

  # Build the gate entry
  local gate_entry
  gate_entry="$(jq -n \
    --arg gn "$gate_name" \
    --arg st "$status" \
    --arg re "$reason" \
    --arg ts "$timestamp" \
    --arg si "$session_id" \
    --arg cm "$command" \
    --arg cn "$challenge_nonce" \
    '{
      gate_name: $gn,
      status: $st,
      reason: $re,
      timestamp: $ts,
      session_id: (if $si == "" then null else $si end),
      command: (if $cm == "" then null else $cm end),
      challenge_nonce: (if $cn == "" then null else $cn end)
    }')"

  if [[ -f "$gate_file" ]]; then
    # Append to existing gate history
    local tmp_file="${gate_file}.tmp"
    jq --argjson entry "$gate_entry" --arg ts "$timestamp" \
      '.gates += [$entry] | .last_updated = $ts' \
      "$gate_file" > "$tmp_file"
    mv "$tmp_file" "$gate_file"
  else
    # Create new gate state file
    jq -n \
      --arg sid "$spec_id" \
      --arg ts "$timestamp" \
      --argjson entry "$gate_entry" \
      '{
        schema_version: "1.0.0",
        spec_id: $sid,
        spec_title: null,
        change_lane: null,
        current_status: "in-progress",
        gates: [$entry],
        last_updated: $ts
      }' > "$gate_file"
  fi
}

# --- Update Spec Metadata ---

forge_gate_state_set_metadata() {
  # Update spec metadata in the gate state file.
  # Usage: forge_gate_state_set_metadata <spec_id> <title> <change_lane> <current_status>
  local spec_id="$1"
  local title="${2:-}"
  local change_lane="${3:-}"
  local current_status="${4:-}"

  if [[ -z "$FORGE_GATES_DIR" ]]; then
    echo "ERROR: Gate state not initialized" >&2
    return 1
  fi

  local gate_file="${FORGE_GATES_DIR}/${spec_id}.json"
  if [[ ! -f "$gate_file" ]]; then
    echo "ERROR: No gate state file for spec ${spec_id}" >&2
    return 1
  fi

  local tmp_file="${gate_file}.tmp"
  local timestamp
  timestamp="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

  jq \
    --arg t "$title" \
    --arg cl "$change_lane" \
    --arg cs "$current_status" \
    --arg ts "$timestamp" \
    '
    (if $t != "" then .spec_title = $t else . end) |
    (if $cl != "" then .change_lane = $cl else . end) |
    (if $cs != "" then .current_status = $cs else . end) |
    .last_updated = $ts
    ' "$gate_file" > "$tmp_file"
  mv "$tmp_file" "$gate_file"
}

# --- Read Gate Outcomes ---

forge_gate_state_get_latest() {
  # Get the latest gate outcome for a specific gate name.
  # Usage: forge_gate_state_get_latest <spec_id> <gate_name>
  # Returns: JSON object of the most recent outcome, or empty string if none.
  local spec_id="$1"
  local gate_name="$2"

  if [[ -z "$FORGE_GATES_DIR" ]]; then
    echo "ERROR: Gate state not initialized" >&2
    return 1
  fi

  local gate_file="${FORGE_GATES_DIR}/${spec_id}.json"
  if [[ ! -f "$gate_file" ]]; then
    echo ""
    return 0
  fi

  jq -r "[.gates[] | select(.gate_name == \"${gate_name}\")] | last // empty" "$gate_file" 2>/dev/null
}

forge_gate_state_get_all() {
  # Get all gate outcomes for a spec.
  # Usage: forge_gate_state_get_all <spec_id>
  # Returns: Full gate state JSON.
  local spec_id="$1"

  if [[ -z "$FORGE_GATES_DIR" ]]; then
    echo "ERROR: Gate state not initialized" >&2
    return 1
  fi

  local gate_file="${FORGE_GATES_DIR}/${spec_id}.json"
  if [[ ! -f "$gate_file" ]]; then
    echo "{}"
    return 0
  fi

  cat "$gate_file"
}

forge_gate_state_check_all_pass() {
  # Check if all gate outcomes for a spec are PASS or CONDITIONAL_PASS.
  # Usage: forge_gate_state_check_all_pass <spec_id>
  # Returns: exit 0 if all pass, exit 1 if any FAIL exists.
  local spec_id="$1"

  if [[ -z "$FORGE_GATES_DIR" ]]; then
    echo "ERROR: Gate state not initialized" >&2
    return 1
  fi

  local gate_file="${FORGE_GATES_DIR}/${spec_id}.json"
  if [[ ! -f "$gate_file" ]]; then
    return 1  # No gates recorded means not passing
  fi

  # Get the latest outcome for each unique gate name
  # If any latest outcome is FAIL, return 1
  local fail_count
  fail_count="$(jq '
    [.gates | group_by(.gate_name)[] | last] |
    map(select(.status == "FAIL")) |
    length
  ' "$gate_file" 2>/dev/null || echo "0")"

  if [[ "$fail_count" -gt 0 ]]; then
    return 1
  fi
  return 0
}

forge_gate_state_get_failures() {
  # Get all FAIL gate outcomes (latest per gate name) for a spec.
  # Usage: forge_gate_state_get_failures <spec_id>
  # Returns: JSON array of failing gates, or "[]" if none.
  local spec_id="$1"

  if [[ -z "$FORGE_GATES_DIR" ]]; then
    echo "[]"
    return
  fi

  local gate_file="${FORGE_GATES_DIR}/${spec_id}.json"
  if [[ ! -f "$gate_file" ]]; then
    echo "[]"
    return
  fi

  jq '[.gates | group_by(.gate_name)[] | last | select(.status == "FAIL")]' "$gate_file" 2>/dev/null || echo "[]"
}

# --- Summary / Display ---

forge_gate_state_summary() {
  # Print a human-readable summary of gate state for a spec.
  # Usage: forge_gate_state_summary <spec_id>
  local spec_id="$1"

  if [[ -z "$FORGE_GATES_DIR" ]]; then
    echo "Gate state not initialized."
    return
  fi

  local gate_file="${FORGE_GATES_DIR}/${spec_id}.json"
  if [[ ! -f "$gate_file" ]]; then
    echo "No gate state for spec ${spec_id}."
    return
  fi

  local title
  title="$(jq -r '.spec_title // "untitled"' "$gate_file")"
  local status
  status="$(jq -r '.current_status // "unknown"' "$gate_file")"
  local gate_count
  gate_count="$(jq '.gates | length' "$gate_file")"

  printf 'Spec %s — %s [%s]\n' "$spec_id" "$title" "$status"
  printf 'Gate outcomes (%s total):\n' "$gate_count"

  # Show latest outcome per gate name
  jq -r '
    [.gates | group_by(.gate_name)[] | last] |
    sort_by(.timestamp) |
    .[] |
    "  \(.status) \(.gate_name) — \(.reason) (\(.timestamp))"
  ' "$gate_file" 2>/dev/null
}

forge_gate_state_list_specs() {
  # List all specs with persistent gate state.
  # Usage: forge_gate_state_list_specs
  if [[ -z "$FORGE_GATES_DIR" || ! -d "$FORGE_GATES_DIR" ]]; then
    echo "No gate state directory."
    return
  fi

  local f
  for f in "$FORGE_GATES_DIR"/*.json; do
    if [[ ! -f "$f" ]]; then
      echo "No gate state files."
      return
    fi
    local sid
    sid="$(jq -r '.spec_id' "$f")"
    local title
    title="$(jq -r '.spec_title // "untitled"' "$f")"
    local status
    status="$(jq -r '.current_status // "unknown"' "$f")"
    local gate_count
    gate_count="$(jq '.gates | length' "$f")"
    local latest_gate
    latest_gate="$(jq -r '.gates | last | "\(.status) \(.gate_name)"' "$f" 2>/dev/null || echo "none")"
    printf '  %s — %s [%s] | %s gates | latest: %s\n' "$sid" "$title" "$status" "$gate_count" "$latest_gate"
  done
}
