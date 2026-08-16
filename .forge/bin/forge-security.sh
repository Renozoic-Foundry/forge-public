#!/usr/bin/env bash
# FORGE Security — Gate authentication CLI (local hardware-key detection)
# Hardware-authenticated gate delivery (Spec 654) is retired — this script
# retains local YubiKey/FIDO2 detection and enrollment bookkeeping, but
# gate approve/reject is prompt-based (see .forge/lib/security.sh) and no
# longer routes through this CLI.
#
# Non-interactive subcommands (--json output, for AI agent orchestration):
#   forge-security.sh --detect --json
#   forge-security.sh --slot-audit --device SERIAL --json
#   forge-security.sh --program --device SERIAL --slot 2 [--save-secret PATH] --json
#   forge-security.sh --enroll --station SERIAL --mobile SERIAL [--channel ID] --json
#   forge-security.sh --challenge CHALLENGE_HEX --device SERIAL --json
#   forge-security.sh --verify --challenge HEX --expected HEX --device SERIAL --json
#   forge-security.sh --status --json
#   forge-security.sh --kill                 Kill switch — invalidate all challenges
#
# Interactive subcommands (legacy, for terminal use without an AI agent):
#   forge-security.sh --enroll [--channel <id>]
#   forge-security.sh --status
#   forge-security.sh --revoke <key-id>
#   forge-security.sh --unlock
set -euo pipefail

# FORGE_SCRIPT_DIR is set by .ps1 wrappers to the real script directory
if [[ -n "${FORGE_SCRIPT_DIR:-}" ]]; then
  FORGE_DIR="$(cd "${FORGE_SCRIPT_DIR}/.." && pwd)"
else
  FORGE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fi
PROJECT_DIR="$(cd "${FORGE_DIR}/.." && pwd)"

# Source shared utilities (forge_source, forge_ensure_yubico_path)
# shellcheck disable=SC1091
source "${FORGE_DIR}/lib/forge-utils.sh"
forge_ensure_yubico_path

forge_source "${FORGE_DIR}/lib/security.sh"
if [[ -f "${FORGE_DIR}/lib/logging.sh" ]]; then
  forge_source "${FORGE_DIR}/lib/logging.sh"
  forge_log_init "forge-security"
fi
forge_security_init "$PROJECT_DIR"

# --- JSON output helpers ---

json_error() {
  local message="$1"
  local code="${2:-1}"
  printf '{"ok":false,"error":"%s"}\n' "$message"
  exit "$code"
}

json_ok() {
  local content="$1"
  printf '{"ok":true,%s}\n' "$content"
}

# --- Non-interactive subcommands (local device management) ---

cmd_detect_json() {
  local devices="[]"

  if command -v ykman &>/dev/null; then
    local ykman_list
    ykman_list="$(ykman list --serials 2>/dev/null)" || true

    if [[ -n "$ykman_list" ]]; then
      while IFS= read -r line; do
        local serial
        serial="$(echo "$line" | grep -oE '[0-9]{6,}')" || true
        if [[ -z "$serial" ]]; then continue; fi

        local info_output
        info_output="$(ykman --device "$serial" info 2>&1)" || true

        local device_type firmware otp_status
        device_type="$(echo "$info_output" | grep "Device type:" | sed 's/.*Device type: *//')" || true
        firmware="$(echo "$info_output" | grep "Firmware version:" | sed 's/.*Firmware version: *//')" || true

        if echo "$info_output" | grep -q "Yubico OTP.*Not available"; then
          otp_status="not_available"
        elif echo "$info_output" | grep -q "Yubico OTP.*Disabled"; then
          otp_status="disabled"
        elif echo "$info_output" | grep -q "Yubico OTP.*Enabled"; then
          otp_status="enabled"
        else
          if echo "$info_output" | grep "Enabled USB interfaces:" | grep -q "OTP"; then
            otp_status="enabled"
          else
            otp_status="unknown"
          fi
        fi

        local otp_supported="true"
        if [[ "$otp_status" == "not_available" ]]; then
          otp_supported="false"
        fi

        local slot1_status="unknown" slot2_status="unknown"
        if [[ "$otp_status" == "enabled" ]]; then
          local otp_info
          otp_info="$(ykman --device "$serial" otp info 2>&1)" || true
          slot1_status="$(echo "$otp_info" | grep "Slot 1:" | sed 's/Slot 1: *//')" || true
          slot2_status="$(echo "$otp_info" | grep "Slot 2:" | sed 's/Slot 2: *//')" || true
        fi

        local slot2_responds="false"
        if [[ "$otp_status" == "enabled" ]]; then
          if ykman --device "$serial" otp calculate 2 0000000000000000000000000000000000000000 &>/dev/null; then
            slot2_responds="true"
          fi
        fi

        devices="$(echo "$devices" | jq \
          --arg serial "$serial" \
          --arg device_type "${device_type:-unknown}" \
          --arg firmware "${firmware:-unknown}" \
          --arg otp_status "$otp_status" \
          --argjson otp_supported "$otp_supported" \
          --arg slot1 "${slot1_status:-unknown}" \
          --arg slot2 "${slot2_status:-unknown}" \
          --argjson slot2_responds "$slot2_responds" \
          '. + [{
            "type": "yubikey",
            "serial": $serial,
            "device_type": $device_type,
            "firmware": $firmware,
            "otp_status": $otp_status,
            "otp_supported": $otp_supported,
            "slot1_status": $slot1,
            "slot2_status": $slot2,
            "slot2_responds": $slot2_responds
          }]')"
      done <<< "$ykman_list"
    fi
  fi

  local fido2_devices="[]"
  if command -v fido2-token &>/dev/null; then
    local fido2_list
    fido2_list="$(fido2-token -L 2>/dev/null)" || true
    if [[ -n "$fido2_list" ]]; then
      while IFS= read -r line; do
        if [[ -z "$line" ]]; then continue; fi
        local dev_path dev_info
        dev_path="$(echo "$line" | cut -d: -f1)" || true
        dev_info="$(echo "$line" | cut -d: -f2-)" || true
        fido2_devices="$(echo "$fido2_devices" | jq \
          --arg path "${dev_path:-unknown}" \
          --arg info "${dev_info:-unknown}" \
          '. + [{"type": "fido2", "path": $path, "info": $info}]')"
      done <<< "$fido2_list"
    fi
  fi

  local providers="[]"
  local yk_count
  yk_count="$(echo "$devices" | jq '[.[] | select(.otp_supported == true and .slot2_responds == true)] | length')"
  if [[ "$yk_count" -gt 0 ]]; then
    providers="$(echo "$providers" | jq '. + [{"provider": "yubikey", "available": true, "device_count": '"$yk_count"'}]')"
  else
    local reason="no YubiKey with OTP support detected"
    if ! command -v ykman &>/dev/null; then reason="ykman not installed"; fi
    providers="$(echo "$providers" | jq --arg r "$reason" '. + [{"provider": "yubikey", "available": false, "reason": $r}]')"
  fi

  local fido2_count
  fido2_count="$(echo "$fido2_devices" | jq 'length')"
  if [[ "$fido2_count" -gt 0 ]]; then
    providers="$(echo "$providers" | jq '. + [{"provider": "fido2", "available": true, "device_count": '"$fido2_count"'}]')"
  else
    local reason="no FIDO2 device detected"
    if ! command -v fido2-token &>/dev/null; then reason="fido2-token not installed"; fi
    providers="$(echo "$providers" | jq --arg r "$reason" '. + [{"provider": "fido2", "available": false, "reason": $r}]')"
  fi

  local enrolled="false"
  local enrollment_info="null"
  local enrolled_keys_file="${FORGE_SECURITY_DIR}/enrolled-keys.json"
  if [[ -f "$enrolled_keys_file" ]]; then
    local key_count
    key_count="$(jq '.keys | length' "$enrolled_keys_file" 2>/dev/null || echo 0)"
    if [[ "$key_count" -ge 2 ]]; then
      enrolled="true"
      enrollment_info="$(jq '{station: (.keys[] | select(.role=="station") | {key_id, serial, status}), mobile: (.keys[] | select(.role=="mobile") | {key_id, serial, status}), channel_id}' "$enrolled_keys_file" 2>/dev/null)" || true
    fi
  fi

  printf '{"ok":true,"devices":%s,"fido2_devices":%s,"providers":%s,"enrolled":%s,"enrollment":%s}\n' \
    "$devices" "$fido2_devices" "$providers" "$enrolled" "${enrollment_info:-null}"
}

cmd_slot_audit_json() {
  local device_serial="$1"

  if [[ -z "$device_serial" ]]; then
    json_error "missing --device SERIAL"
  fi

  if ! command -v ykman &>/dev/null; then
    json_error "ykman not installed"
  fi

  local info_output
  info_output="$(ykman --device "$device_serial" info 2>&1)" || json_error "device $device_serial not found or not accessible"

  local device_type
  device_type="$(echo "$info_output" | grep "Device type:" | sed 's/.*Device type: *//')" || true

  local otp_status="unknown"
  if echo "$info_output" | grep -q "Yubico OTP.*Not available"; then
    otp_status="not_available"
    printf '{"ok":true,"device_serial":"%s","device_type":"%s","otp_status":"not_available","otp_supported":false,"message":"This %s does not support OTP slots. HMAC-SHA1 challenge-response requires a YubiKey 5 or YubiKey 4 series."}\n' \
      "$device_serial" "${device_type:-unknown}" "${device_type:-device}"
    return 0
  elif echo "$info_output" | grep -q "Yubico OTP.*Disabled"; then
    otp_status="disabled"
    printf '{"ok":true,"device_serial":"%s","device_type":"%s","otp_status":"disabled","otp_supported":true,"otp_disabled":true,"message":"OTP is disabled on this device. Re-enable with: ykman config usb --enable OTP"}\n' \
      "$device_serial" "${device_type:-unknown}"
    return 0
  fi

  local otp_info
  otp_info="$(ykman --device "$device_serial" otp info 2>&1)" || json_error "failed to read OTP info from device $device_serial"

  local slot1_status slot2_status
  slot1_status="$(echo "$otp_info" | grep "Slot 1:" | sed 's/Slot 1: *//')" || true
  slot2_status="$(echo "$otp_info" | grep "Slot 2:" | sed 's/Slot 2: *//')" || true

  local slot2_responds="false"
  if ykman --device "$device_serial" otp calculate 2 0000000000000000000000000000000000000000 &>/dev/null; then
    slot2_responds="true"
  fi

  local slot2_warning="none"
  if [[ "$slot2_responds" == "true" ]]; then
    slot2_warning="slot2_programmed_irreversible"
  fi

  printf '{"ok":true,"device_serial":"%s","device_type":"%s","otp_status":"enabled","otp_supported":true,"slot1_status":"%s","slot1_note":"FORGE never modifies slot 1","slot2_status":"%s","slot2_responds":%s,"slot2_warning":"%s"}\n' \
    "$device_serial" "${device_type:-unknown}" "${slot1_status:-unknown}" "${slot2_status:-unknown}" "$slot2_responds" "$slot2_warning"
}

cmd_program_json() {
  local device_serial="$1"
  local slot="${2:-2}"
  local save_secret_path="${3:-}"

  if [[ -z "$device_serial" ]]; then
    json_error "missing --device SERIAL"
  fi

  if ! command -v ykman &>/dev/null; then
    json_error "ykman not installed"
  fi

  local program_output
  program_output="$(ykman --device "$device_serial" otp chalresp --generate "$slot" --force 2>&1)" || json_error "failed to program slot $slot on device $device_serial: $program_output"

  local secret
  secret="$(echo "$program_output" | grep -oiE '[0-9a-f]{40}' | head -1)" || true

  if [[ -z "$secret" ]]; then
    secret="$(echo "$program_output" | grep -i 'key' | grep -oiE '[0-9a-f]{40}' | head -1)" || true
  fi

  local saved_to=""
  if [[ -n "$save_secret_path" && -n "$secret" ]]; then
    local secret_dir
    secret_dir="$(dirname "$save_secret_path")"
    mkdir -p "$secret_dir"
    printf '%s\n' "$secret" > "$save_secret_path"
    chmod 600 "$save_secret_path"
    saved_to="$save_secret_path"
  fi

  local verify_response
  verify_response="$(ykman --device "$device_serial" otp calculate "$slot" 0000000000000000000000000000000000000000 2>&1)" || true

  printf '{"ok":true,"device_serial":"%s","slot":%s,"secret":"%s","saved_to":"%s","verified":%s}\n' \
    "$device_serial" "$slot" "${secret:-unknown}" "$saved_to" \
    "$(if [[ -n "$verify_response" ]]; then echo "true"; else echo "false"; fi)"
}

cmd_enroll_json() {
  local station_serial="$1"
  local mobile_serial="$2"
  local channel_id="${3:-}"

  if [[ -z "$station_serial" || -z "$mobile_serial" ]]; then
    json_error "missing --station SERIAL and/or --mobile SERIAL"
  fi

  if [[ "$station_serial" == "$mobile_serial" ]]; then
    json_error "station and mobile must be different keys (both are $station_serial)"
  fi

  local test_challenge="0000000000000000000000000000000000000000"
  local yubikey_slot="${FORGE_YUBIKEY_SLOT:-2}"

  if ! ykman --device "$station_serial" otp calculate "$yubikey_slot" "$test_challenge" &>/dev/null; then
    json_error "station key $station_serial: HMAC-SHA1 not programmed in slot ${yubikey_slot}"
  fi

  if ! ykman --device "$mobile_serial" otp calculate "$yubikey_slot" "$test_challenge" &>/dev/null; then
    json_error "mobile key $mobile_serial: HMAC-SHA1 not programmed in slot ${yubikey_slot}"
  fi

  local station_resp mobile_resp
  station_resp="$(ykman --device "$station_serial" otp calculate "$yubikey_slot" "$test_challenge" 2>/dev/null)" || true
  mobile_resp="$(ykman --device "$mobile_serial" otp calculate "$yubikey_slot" "$test_challenge" 2>/dev/null)" || true

  if [[ "$station_resp" == "$mobile_resp" ]]; then
    json_error "both keys produce identical responses — they may share the same secret"
  fi

  local timestamp
  timestamp="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  local enrolled_keys_file="${FORGE_SECURITY_DIR}/enrolled-keys.json"
  cat > "$enrolled_keys_file" <<ENDJSON
{
  "schema_version": "1.0.0",
  "enrolled_at": "${timestamp}",
  "channel_id": "${channel_id}",
  "yubikey_slot": ${yubikey_slot},
  "keys": [
    {
      "role": "station",
      "key_id": "YK-${station_serial}",
      "serial": "${station_serial}",
      "enrolled_at": "${timestamp}",
      "status": "active"
    },
    {
      "role": "mobile",
      "key_id": "YK-${mobile_serial}",
      "serial": "${mobile_serial}",
      "enrolled_at": "${timestamp}",
      "status": "active"
    }
  ]
}
ENDJSON

  forge_security_log "enrollment" "completed" "station=YK-${station_serial} mobile=YK-${mobile_serial}" "local" "success"

  printf '{"ok":true,"station":{"key_id":"YK-%s","serial":"%s"},"mobile":{"key_id":"YK-%s","serial":"%s"},"channel_id":"%s","enrolled_at":"%s"}\n' \
    "$station_serial" "$station_serial" "$mobile_serial" "$mobile_serial" "${channel_id:-unset}" "$timestamp"
}

cmd_challenge_json() {
  local challenge_hex="$1"
  local device_serial="$2"

  if [[ -z "$challenge_hex" || -z "$device_serial" ]]; then
    json_error "missing --challenge HEX and/or --device SERIAL"
  fi

  if ! command -v ykman &>/dev/null; then
    json_error "ykman not installed"
  fi

  local yubikey_slot="${FORGE_YUBIKEY_SLOT:-2}"
  local response
  response="$(ykman --device "$device_serial" otp calculate "$yubikey_slot" "$challenge_hex" 2>&1)" || json_error "challenge-response failed on device $device_serial: $response"

  printf '{"ok":true,"device_serial":"%s","challenge":"%s","response":"%s"}\n' \
    "$device_serial" "$challenge_hex" "$response"
}

cmd_verify_json() {
  local challenge_hex="$1"
  local expected_hex="$2"
  local device_serial="$3"

  if [[ -z "$challenge_hex" || -z "$expected_hex" || -z "$device_serial" ]]; then
    json_error "missing --challenge, --expected, or --device"
  fi

  local yubikey_slot="${FORGE_YUBIKEY_SLOT:-2}"
  local response
  response="$(ykman --device "$device_serial" otp calculate "$yubikey_slot" "$challenge_hex" 2>&1)" || json_error "challenge-response failed on device $device_serial"

  local match="false"
  if [[ "$response" == "$expected_hex" ]]; then
    match="true"
  fi

  printf '{"ok":true,"match":%s,"device_serial":"%s","challenge":"%s","response":"%s","expected":"%s"}\n' \
    "$match" "$device_serial" "$challenge_hex" "$response" "$expected_hex"
}

cmd_status_json() {
  local enrolled="false"
  local station="null"
  local mobile="null"
  local channel_id=""
  local slot=""
  local enrolled_keys_file="${FORGE_SECURITY_DIR}/enrolled-keys.json"

  if [[ -f "$enrolled_keys_file" ]]; then
    local key_count
    key_count="$(jq '.keys | length' "$enrolled_keys_file" 2>/dev/null || echo 0)"
    if [[ "$key_count" -ge 2 ]]; then
      enrolled="true"
      station="$(jq '{key_id: (.keys[] | select(.role=="station") | .key_id), serial: (.keys[] | select(.role=="station") | .serial), status: (.keys[] | select(.role=="station") | .status)}' "$enrolled_keys_file" 2>/dev/null)" || station="null"
      mobile="$(jq '{key_id: (.keys[] | select(.role=="mobile") | .key_id), serial: (.keys[] | select(.role=="mobile") | .serial), status: (.keys[] | select(.role=="mobile") | .status)}' "$enrolled_keys_file" 2>/dev/null)" || mobile="null"
      channel_id="$(jq -r '.channel_id // ""' "$enrolled_keys_file" 2>/dev/null)" || true
      slot="$(jq -r '.yubikey_slot // 2' "$enrolled_keys_file" 2>/dev/null)" || true
    fi
  fi

  local pending_count=0
  if [[ -d "$FORGE_CHALLENGES_DIR" ]]; then
    local f
    for f in "$FORGE_CHALLENGES_DIR"/*.json; do
      if [[ ! -f "$f" ]]; then continue; fi
      local s
      s="$(jq -r '.status' "$f")"
      if [[ "$s" == "pending" ]]; then
        pending_count=$((pending_count + 1))
      fi
    done
  fi

  printf '{"ok":true,"enrolled":%s,"station":%s,"mobile":%s,"channel_id":"%s","yubikey_slot":"%s","pending_challenges":%d}\n' \
    "$enrolled" "$station" "$mobile" "$channel_id" "${slot:-2}" "$pending_count"
}

# --- Usage ---

usage() {
  echo "Usage: forge-security.sh <command> [options]"
  echo ""
  echo "Non-interactive commands (--json output, for AI agent orchestration):"
  echo "  --detect --json                                    List connected devices and providers"
  echo "  --slot-audit --device SERIAL --json                Show slot status for a device"
  echo "  --program --device SERIAL --slot N [--save-secret PATH] --json  Program a slot"
  echo "  --enroll --station SERIAL --mobile SERIAL [--channel ID] --json Enroll two keys"
  echo "  --challenge HEX --device SERIAL --json             Challenge-response"
  echo "  --verify --challenge HEX --expected HEX --device SERIAL --json  Verify response"
  echo "  --status --json                                    Enrollment and security status"
  echo "  --kill                                             Kill switch — invalidate all challenges"
  echo ""
  echo "Interactive commands (legacy, for terminal use):"
  echo "  --enroll --station SERIAL --mobile SERIAL [--channel <id>]   Non-interactive enrollment"
  echo "  --status                    Human-readable status"
  echo "  --unlock                    Clear channel lockout"
  echo ""
  echo "Gate approve/reject is prompt-based (chat approval) and no longer routes through this CLI."
}

# --- Argument parsing ---

if [[ $# -lt 1 ]]; then
  usage
  exit 1
fi

COMMAND="$1"
shift

JSON_MODE=false
DEVICE_SERIAL=""
SLOT_NUM="2"
SAVE_SECRET_PATH=""
STATION_SERIAL=""
MOBILE_SERIAL=""
CHANNEL_ID=""
CHALLENGE_HEX=""
EXPECTED_HEX=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --json)         JSON_MODE=true; shift ;;
    --device)       DEVICE_SERIAL="${2:-}"; shift 2 ;;
    --slot)         SLOT_NUM="${2:-2}"; shift 2 ;;
    --save-secret)  SAVE_SECRET_PATH="${2:-}"; shift 2 ;;
    --station)      STATION_SERIAL="${2:-}"; shift 2 ;;
    --mobile)       MOBILE_SERIAL="${2:-}"; shift 2 ;;
    --channel)      CHANNEL_ID="${2:-}"; shift 2 ;;
    --challenge)    CHALLENGE_HEX="${2:-}"; shift 2 ;;
    --expected)     EXPECTED_HEX="${2:-}"; shift 2 ;;
    *)              shift ;;
  esac
done

if [[ -n "${FORGE_DIR:-}" ]]; then
  if [[ -f "${FORGE_DIR}/lib/logging.sh" ]]; then
    forge_log_debug "Command: ${COMMAND} json=${JSON_MODE}" 2>/dev/null || true
  fi
fi

case "$COMMAND" in
  --detect)
    if $JSON_MODE; then
      cmd_detect_json
    else
      echo "Use --detect --json for structured output."
      exit 1
    fi
    ;;

  --slot-audit)
    if $JSON_MODE; then
      cmd_slot_audit_json "$DEVICE_SERIAL"
    else
      echo "Use --slot-audit --device SERIAL --json for structured output."
      exit 1
    fi
    ;;

  --program)
    if $JSON_MODE; then
      cmd_program_json "$DEVICE_SERIAL" "$SLOT_NUM" "$SAVE_SECRET_PATH"
    else
      echo "Use --program --device SERIAL --slot N --json for structured output."
      exit 1
    fi
    ;;

  --enroll)
    if [[ -n "$STATION_SERIAL" && -n "$MOBILE_SERIAL" ]]; then
      cmd_enroll_json "$STATION_SERIAL" "$MOBILE_SERIAL" "$CHANNEL_ID"
    else
      echo "Use --station SERIAL --mobile SERIAL --json for non-interactive enrollment." >&2
      exit 1
    fi
    ;;

  --kill)
    forge_gate_kill
    ;;

  --challenge)
    if $JSON_MODE; then
      cmd_challenge_json "$CHALLENGE_HEX" "$DEVICE_SERIAL"
    else
      echo "Use --challenge HEX --device SERIAL --json for structured output."
      exit 1
    fi
    ;;

  --verify)
    if $JSON_MODE; then
      cmd_verify_json "$CHALLENGE_HEX" "$EXPECTED_HEX" "$DEVICE_SERIAL"
    else
      echo "Use --verify --challenge HEX --expected HEX --device SERIAL --json for structured output."
      exit 1
    fi
    ;;

  --status)
    if $JSON_MODE; then
      cmd_status_json
    else
      forge_gate_status
    fi
    ;;

  --revoke)
    echo "ERROR: --revoke is not supported without hardware-authenticated key management." >&2
    exit 1
    ;;

  --unlock)
    echo "Channel lockout cleared."
    ;;

  --help|-h)
    usage
    ;;

  *)
    echo "Unknown command: $COMMAND" >&2
    usage
    exit 1
    ;;
esac
