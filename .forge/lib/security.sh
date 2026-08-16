#!/usr/bin/env bash
# FORGE security.sh — Gate authentication library (prompt-based)
# Sourced by other FORGE scripts. Do not execute directly.
#
# Spec 654: the hardware-authenticated gate tier was deprecated — the operator
# will not use hardware auth, and Claude Code's native remote-control
# capability covers the async-review use case that tier served. The
# only supported gate.provider is `prompt` (chat-based approval). Lane B
# uses the same prompt-based gates as Lane A now; it keeps every other Lane B
# control (compliance profile, sealing, dual validation, traceability) and
# loses only the hardware-authentication tier. See docs/sessions/watchlist.md
# for the re-add trigger (hardware-authenticated gates).
#
# Dependencies: jq.

FORGE_SECURITY_DIR=""
FORGE_CHALLENGES_DIR=""
FORGE_SECURITY_AUDIT=""

# --- Gate provider configuration ---
FORGE_GATE_PROVIDER="${FORGE_GATE_PROVIDER:-prompt}"   # prompt (only supported value)
FORGE_GATE_TIMEOUT="${FORGE_GATE_TIMEOUT:-1800}"       # 30 minutes default
FORGE_LANE="${FORGE_LANE:-A}"                          # A or B

_forge_resolve_provider() {
  # Resolve the effective gate provider. Only "prompt" is supported — Lane B
  # uses the same prompt-based gates as Lane A (hardware authentication was
  # retired; see docs/sessions/watchlist.md for the re-add trigger).
  # Sets FORGE_EFFECTIVE_PROVIDER to "prompt".
  local provider="${FORGE_GATE_PROVIDER}"

  case "$provider" in
    prompt)
      FORGE_EFFECTIVE_PROVIDER="prompt"
      ;;
    *)
      echo "ERROR: Unknown gate.provider '${provider}'. Valid value: prompt." >&2
      return 1
      ;;
  esac
}

# --- Initialization ---

forge_security_init() {
  local project_dir="$1"
  FORGE_SECURITY_DIR="${project_dir}/.forge/security"
  FORGE_CHALLENGES_DIR="${FORGE_SECURITY_DIR}/challenges"
  FORGE_SECURITY_AUDIT="${FORGE_SECURITY_DIR}/audit.log"

  mkdir -p "$FORGE_CHALLENGES_DIR"
}

# --- Security Audit Logging ---

forge_security_log() {
  local event_type="$1"
  local event="$2"
  local detail="${3:-}"
  local channel="${4:-local}"
  local result="${5:-}"

  if [[ -z "$FORGE_SECURITY_AUDIT" ]]; then
    echo "ERROR: Security not initialized — call forge_security_init first" >&2
    return 1
  fi

  local timestamp
  timestamp="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  echo "${timestamp} [${event_type}] ${event}: ${detail} channel=${channel} result=${result}" >> "$FORGE_SECURITY_AUDIT"
}

# --- Gate Request ---

forge_gate_request() {
  # Request gate approval for a spec/gate combination (prompt-based approval
  # via chat response).
  local spec_id="$1"
  local gate_type="$2"
  local gate_id="${spec_id}-${gate_type}"

  if ! _forge_resolve_provider; then
    return 1
  fi

  forge_security_log "gate" "prompt-approve-request" "gate=${gate_id}" "local" "pending"
  printf '{"gate_id":"%s","provider":"prompt","status":"awaiting_approval","message":"Approve gate %s? Reply: approve or reject <reason>"}\n' \
    "$gate_id" "$gate_id"
}

forge_gate_reject() {
  # Record a gate rejection.
  local spec_id="$1"
  local gate_type="$2"
  local reason="${3:-}"
  local gate_id="${spec_id}-${gate_type}"

  if ! _forge_resolve_provider; then
    return 1
  fi

  forge_security_log "gate" "prompt-reject" "gate=${gate_id} reason=${reason}" "local" "rejected"
  printf '{"gate_id":"%s","provider":"prompt","status":"rejected","reason":"%s"}\n' \
    "$gate_id" "$reason"
}

# --- Kill Switch ---

forge_gate_kill() {
  # Invalidate all outstanding gate challenges.
  forge_security_invalidate_all_challenges
}

# --- Detection ---

forge_gate_detect() {
  # Hardware-authenticated gate detection is retired — always prompt-based.
  printf '{"provider":"prompt","hardware_available":false,"message":"Hardware-authenticated gates are retired. Using prompt-based approval."}\n'
}

# --- Status ---

forge_gate_status() {
  # Show gate authentication status.
  local provider="${FORGE_GATE_PROVIDER}"
  printf '{"provider":"%s","effective_provider":"prompt","message":"Prompt-based approval (hardware-authenticated gates are retired)."}\n' \
    "$provider"
}

# --- Challenge Lifecycle ---

forge_security_invalidate_all_challenges() {
  if [[ ! -d "$FORGE_CHALLENGES_DIR" ]]; then
    echo "Invalidated 0 outstanding challenge(s)."
    return
  fi

  local count=0
  local timestamp
  timestamp="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

  local challenge_file
  for challenge_file in "$FORGE_CHALLENGES_DIR"/*.json; do
    if [[ ! -f "$challenge_file" ]]; then continue; fi
    local status
    status="$(jq -r '.status' "$challenge_file")"
    if [[ "$status" == "pending" ]]; then
      local tmp_file="${challenge_file}.tmp"
      jq ".status = \"invalidated\" | .invalidated_at = \"${timestamp}\"" "$challenge_file" > "$tmp_file"
      mv "$tmp_file" "$challenge_file"
      count=$((count + 1))
    fi
  done

  forge_security_log "challenge" "invalidate-all" "count=${count}" "local" "success"
  echo "Invalidated ${count} outstanding challenge(s)."
}

# --- Gate Message Rendering ---

forge_security_render_gate_message() {
  local spec_id="$1"
  local gate_type="$2"
  local test_passed="${3:-0}"
  local test_total="${4:-0}"
  local lint_clean="${5:-true}"
  local files_changed="${6:-0}"
  local insertions="${7:-0}"
  local deletions="${8:-0}"

  if ! _forge_resolve_provider; then
    return 1
  fi

  local test_icon="pass"
  if [[ "$test_passed" != "$test_total" ]]; then
    test_icon="fail"
  fi

  local lint_text="clean"
  if [[ "$lint_clean" != "true" ]]; then
    lint_text="issues found"
  fi

  printf 'FORGE — Spec %s %s\n' "$spec_id" "$gate_type"
  printf 'Gate: prompt-based approval\n'
  echo ""
  printf 'Tests: %s/%s %s\n' "$test_passed" "$test_total" "$test_icon"
  printf 'Lint: %s\n' "$lint_text"
  printf 'Diff: %s files changed, +%s -%s\n' "$files_changed" "$insertions" "$deletions"
  echo ""
  printf '→ Reply: approve\n'
  printf '→ Or reply: reject <reason>\n'
  printf '→ Or reply: show diff | show tests | defer\n'
}

# --- Response Parsing ---

forge_security_parse_response() {
  local raw_text="$1"
  local text
  text="$(printf '%s' "$raw_text" | tr '[:upper:]' '[:lower:]' | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')"

  # Approve
  if [[ "$text" == "approve" ]]; then
    printf '{"decision":"approve"}\n'
    return
  fi

  # Reject — "reject reason text"
  if [[ "$text" =~ ^reject[[:space:]]+(.*) ]]; then
    local reason="${BASH_REMATCH[1]}"
    printf '{"decision":"reject","reason":"%s"}\n' "$reason"
    return
  fi

  # Query — "show diff", "show tests", etc.
  if [[ "$text" =~ ^show[[:space:]]+(diff|tests|coverage|log|spec) ]]; then
    local query_type="${BASH_REMATCH[1]}"
    printf '{"decision":"query","query_type":"%s"}\n' "$query_type"
    return
  fi

  # Defer — "defer" or "defer until <datetime>"
  if [[ "$text" == "defer" ]]; then
    printf '{"decision":"defer"}\n'
    return
  fi
  if [[ "$text" =~ ^defer[[:space:]]+until[[:space:]]+(.*) ]]; then
    local resume_at="${BASH_REMATCH[1]}"
    printf '{"decision":"defer","resume_at":"%s"}\n' "$resume_at"
    return
  fi

  # Unrecognized
  printf '{"decision":"unknown","raw":"%s"}\n' "$raw_text"
}
