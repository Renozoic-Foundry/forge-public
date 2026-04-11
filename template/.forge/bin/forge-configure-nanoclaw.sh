#!/usr/bin/env bash
# FORGE NanoClaw Configuration Wizard — FALLBACK terminal mode
# Interactive walkthrough: program YubiKeys → enroll → configure → test
# Usage: forge-configure-nanoclaw.sh [--step N] [--check-only]
#
# RECOMMENDED: Use /configure-nanoclaw from your AI agent instead.
# This script is the fallback for environments without an AI agent.
# The slash command runs forge-security.sh behind the scenes and handles
# all user interaction in the conversation — no terminal prompts needed.
#
# Run after forge-setup-nanoclaw.sh has installed prerequisites.
set -euo pipefail

# FORGE_SCRIPT_DIR is set by .ps1 wrappers to the real script directory
# (BASH_SOURCE[0] points to a temp file when launched via .ps1)
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

# Source logging library and security library
forge_source "${FORGE_DIR}/lib/logging.sh"
forge_log_init "forge-configure-nanoclaw"

forge_source "${FORGE_DIR}/lib/security.sh"
forge_security_init "$PROJECT_DIR"

# Source auth-provider library as fallback when PAL is not installed.
# When PAL is available, forge_gate_* functions in security.sh delegate to PAL CLI.
# auth-provider.sh provides legacy forge_auth_* functions for direct device interaction.
if [[ -f "${FORGE_DIR}/lib/auth-provider.sh" ]]; then
  forge_source "${FORGE_DIR}/lib/auth-provider.sh"
fi

START_STEP=1
CHECK_ONLY=false

# Colors for interactive display (logging library handles log output colors)
RED=""
GREEN=""
YELLOW=""
CYAN=""
BOLD=""
RESET=""
if [[ -t 1 ]]; then
  RED="\033[0;31m"
  GREEN="\033[0;32m"
  YELLOW="\033[1;33m"
  CYAN="\033[0;36m"
  BOLD="\033[1m"
  RESET="\033[0m"
fi

# Aliases for backward compat within this script
info()  { forge_log_info "$1"; }
warn()  { forge_log_warn "$1"; }
fail()  { forge_log_error "$1"; }
step()  { forge_log_step "Step $1"; }

prompt_enter() {
  printf "${YELLOW}→${RESET} %s " "$1"
  read -r
}

prompt_yes_no() {
  local question="$1"
  local default="${2:-n}"
  local hint="y/N"
  if [[ "$default" == "y" ]]; then hint="Y/n"; fi
  printf "${YELLOW}→${RESET} %s (%s): " "$question" "$hint"
  local answer
  read -r answer
  answer="${answer:-$default}"
  case "$answer" in
    [yY]*) return 0 ;;
    *) return 1 ;;
  esac
}

prompt_value() {
  local label="$1"
  local default="${2:-}"
  if [[ -n "$default" ]]; then
    printf "${YELLOW}→${RESET} %s [%s]: " "$label" "$default"
  else
    printf "${YELLOW}→${RESET} %s: " "$label"
  fi
  local value
  read -r value
  echo "${value:-$default}"
}

# --- Parse args ---
while [[ $# -gt 0 ]]; do
  case "$1" in
    --step)   START_STEP="${2:-1}"; shift 2 ;;
    --check-only) CHECK_ONLY=true; shift ;;
    --help|-h)
      echo "Usage: forge-configure-nanoclaw.sh [--step N] [--check-only]"
      echo ""
      echo "Steps:"
      echo "  1  Program YubiKeys (HMAC-SHA1 slot 2)"
      echo "  2  Enroll keys with FORGE"
      echo "  3  Configure AGENTS.md"
      echo "  4  Test NanoClaw connectivity"
      echo "  5  End-to-end verification"
      echo ""
      echo "Options:"
      echo "  --step N       Jump to a specific step"
      echo "  --check-only   Show status without executing"
      exit 0
      ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

# --- Portable sed -i ---
sed_inplace() {
  if sed --version 2>/dev/null | grep -q GNU; then
    sed -i "$@"
  else
    sed -i '' "$@"
  fi
}

# --- Step check functions ---

check_step_1() {
  # Check if a YubiKey is present and slot 2 is programmed (via ykman)
  if command -v ykman &>/dev/null; then
    local slot_info=""
    slot_info="$(ykman otp info 2>/dev/null)" || true
    if echo "$slot_info" | grep -q "Slot 2:" && ! echo "$slot_info" | grep -q "Slot 2:.*empty"; then
      return 0
    fi
  fi
  return 1
}

check_step_2() {
  forge_security_check_enrolled
}

check_step_3() {
  local agents_file="${PROJECT_DIR}/AGENTS.md"
  if [[ -f "$agents_file" ]]; then
    if grep -q 'enabled: true' "$agents_file" 2>/dev/null; then
      return 0
    fi
  fi
  return 1
}

check_step_4() {
  local agents_file="${PROJECT_DIR}/AGENTS.md"
  local endpoint
  endpoint="$(grep 'endpoint:' "$agents_file" 2>/dev/null | head -1 | sed 's/.*endpoint: *//' | tr -d ' ')" || true
  if [[ -n "$endpoint" ]]; then
    local endpoint_clean="${endpoint%/}"
    if curl -s --connect-timeout 3 -o /dev/null -w '' "${endpoint_clean}/api/health" 2>/dev/null; then
      return 0
    fi
  fi
  return 1
}

check_step_5() {
  # E2E test is always manual — return 1 to offer it
  return 1
}

# --- Step status display ---

show_status() {
  echo ""
  printf '%b%s%b\n' "${BOLD}" "Current status:" "${RESET}"
  local labels=("Program YubiKeys (HMAC-SHA1 slot 2)" "Enroll keys with FORGE" "Configure AGENTS.md" "Test NanoClaw connectivity" "End-to-end verification")
  for i in 1 2 3 4 5; do
    local label="${labels[$((i-1))]}"
    if "check_step_${i}" 2>/dev/null; then
      printf "  ${GREEN}[${i}]${RESET} %-45s ${GREEN}DONE${RESET}\n" "$label"
    else
      printf "  ${YELLOW}[${i}]${RESET} %-45s ${YELLOW}—${RESET}\n" "$label"
    fi
  done
  echo ""
}

# --- Step execution functions ---

run_step_1() {
  step "1: Program YubiKeys"
  echo ""
  echo "Each YubiKey needs HMAC-SHA1 challenge-response programmed into slot 2."
  echo "This is a one-time operation per key. Slot 1 (OTP) is NEVER touched."
  echo ""

  # --- Station key ---
  prompt_enter "Insert your STATION key (desktop USB) and press Enter..."

  # Model detection + safety pre-flight via auth-provider (R1-R11)
  info "Detecting device..."
  echo ""
  if ! forge_auth_enroll_yubikey; then
    fail "Station key enrollment failed."
    return 1
  fi
  local station_serial
  station_serial="$(ykman info 2>/dev/null | grep "Serial number:" | sed 's/.*Serial number: *//')" || true
  info "Station key ready (serial: ${station_serial})"

  # Verify station key challenge-response
  local test_challenge="0000000000000000000000000000000000000000"
  local station_response=""
  station_response="$(forge_auth_challenge_yubikey "$test_challenge" 2>/dev/null)" || true
  if [[ -z "$station_response" ]]; then
    fail "Station key verification failed."
    return 1
  fi
  info "Station key verified (response: ${station_response:0:8}...)"

  # --- Mobile key ---
  echo ""
  prompt_enter "Remove STATION key. Insert your MOBILE key and press Enter..."

  info "Detecting device..."
  echo ""
  if ! forge_auth_enroll_yubikey; then
    fail "Mobile key enrollment failed."
    return 1
  fi
  local mobile_serial
  mobile_serial="$(ykman info 2>/dev/null | grep "Serial number:" | sed 's/.*Serial number: *//')" || true

  if [[ -n "$station_serial" && "$mobile_serial" == "$station_serial" ]]; then
    fail "Same key detected (serial ${mobile_serial}). You need two DIFFERENT YubiKeys."
    return 1
  fi
  info "Mobile key ready (serial: ${mobile_serial})"

  # Verify mobile key challenge-response
  local mobile_response=""
  mobile_response="$(forge_auth_challenge_yubikey "$test_challenge" 2>/dev/null)" || true
  if [[ -z "$mobile_response" ]]; then
    fail "Mobile key verification failed."
    return 1
  fi
  info "Mobile key verified (response: ${mobile_response:0:8}...)"

  # Verify different keys
  if [[ "$station_response" == "$mobile_response" ]]; then
    fail "Both keys returned the same response — they may have the same secret. Reprogram one."
    return 1
  fi
  info "Both keys return different responses — confirmed distinct."

  echo ""
  info "Step 1 complete. Both YubiKeys programmed."
  echo ""
  prompt_enter "Re-insert STATION key into desktop USB and press Enter..."
}

run_step_2() {
  step "2: Enroll Keys with FORGE"
  echo ""

  if forge_security_check_enrolled 2>/dev/null; then
    local station_id mobile_id
    station_id="$(forge_security_get_key_id "station")"
    mobile_id="$(forge_security_get_key_id "mobile")"
    info "Already enrolled:"
    info "  Station: ${station_id}"
    info "  Mobile:  ${mobile_id}"
    echo ""
    if ! prompt_yes_no "Re-enroll with new keys?"; then
      info "Keeping existing enrollment."
      return 0
    fi
  fi

  # --- Messaging platform selection ---
  echo "NanoClaw sends gate decisions (approve/reject) to your messaging platform."
  echo "You can configure one or more platforms for redundancy."
  echo ""
  echo "  Supported platforms:"
  echo "    [1] Telegram  — inline approve/reject buttons, easy bot setup"
  echo "    [2] Slack     — Block Kit buttons, workspace bot"
  echo "    [3] Discord   — message components, webhook or bot"
  echo "    [4] MS Teams  — Adaptive Cards, Power Automate webhook"
  echo "    [5] Skip      — configure later in AGENTS.md"
  echo ""

  local platforms_json="[]"
  local adding_platforms=true

  while $adding_platforms; do
    local platform_choice
    platform_choice="$(prompt_value "Select a platform (1-5)" "5")"

    case "$platform_choice" in
      1) # Telegram
        echo ""
        echo "  Telegram setup:"
        echo "    1. Create a bot via @BotFather in Telegram (send /newbot)"
        echo "    2. Copy the bot token (looks like: 123456:ABC-DEF1234ghIkl-zyx57W2v1u123ew11)"
        echo "    3. Start a chat with your new bot (send /start)"
        echo "    4. To find your chat ID, send any message to your bot, then run:"
        echo "       curl -s https://api.telegram.org/bot<TOKEN>/getUpdates | jq '.result[0].message.chat.id'"
        echo ""

        local tg_token tg_chat_id
        tg_token="$(prompt_value "Bot token (or 'skip' to enter later)")"
        if [[ "$tg_token" == "skip" || -z "$tg_token" ]]; then
          warn "Telegram bot token not provided. You can set it later in AGENTS.md."
        else
          # Offer to auto-discover chat ID
          echo ""
          echo "  Attempting to discover your chat ID..."
          echo "  Make sure you have sent /start to the bot, then press Enter."
          prompt_enter "Press Enter to query the bot for your chat ID..."

          local tg_updates
          tg_updates="$(curl -s "https://api.telegram.org/bot${tg_token}/getUpdates" 2>/dev/null)" || true
          tg_chat_id="$(echo "$tg_updates" | jq -r '.result[-1].message.chat.id // empty' 2>/dev/null)" || true

          if [[ -n "$tg_chat_id" ]]; then
            info "Discovered chat ID: ${tg_chat_id}"
            if ! prompt_yes_no "Use this chat ID?" "y"; then
              tg_chat_id="$(prompt_value "Enter chat ID manually")"
            fi
          else
            warn "Could not discover chat ID automatically."
            echo "  Possible reasons: no messages sent to bot yet, or invalid token."
            echo "  You can find it manually:"
            echo "    1. Send /start to your bot in Telegram"
            echo "    2. Run: curl -s https://api.telegram.org/bot${tg_token}/getUpdates | jq '.result[0].message.chat.id'"
            echo ""
            tg_chat_id="$(prompt_value "Enter chat ID (or 'skip')")"
            if [[ "$tg_chat_id" == "skip" ]]; then tg_chat_id=""; fi
          fi

          if [[ -n "$tg_chat_id" ]]; then
            platforms_json="$(echo "$platforms_json" | jq --arg t "$tg_token" --arg c "$tg_chat_id" \
              '. + [{"platform": "telegram", "token": $t, "channel_id": $c}]')"
            info "Telegram configured (chat ID: ${tg_chat_id})"
          else
            warn "Telegram added without chat ID. Set it later in AGENTS.md."
            platforms_json="$(echo "$platforms_json" | jq --arg t "$tg_token" \
              '. + [{"platform": "telegram", "token": $t, "channel_id": "unset"}]')"
          fi
        fi
        ;;

      2) # Slack
        echo ""
        echo "  Slack setup:"
        echo "    1. Create a Slack App at https://api.slack.com/apps"
        echo "    2. Add bot scopes: chat:write, im:write, commands"
        echo "    3. Install the app to your workspace"
        echo "    4. Copy the Bot User OAuth Token (starts with xoxb-)"
        echo "    5. Find channel ID: right-click channel → View channel details → ID at bottom"
        echo "       Or for DMs: the bot can message you directly using your Slack user ID"
        echo ""

        local slack_token slack_channel
        slack_token="$(prompt_value "Bot token (xoxb-...) or 'skip'")"
        if [[ "$slack_token" == "skip" || -z "$slack_token" ]]; then
          warn "Slack token not provided. Configure later in AGENTS.md."
        else
          slack_channel="$(prompt_value "Channel or user ID (e.g., C01234ABCDE or U01234ABCDE)")"
          if [[ -n "$slack_channel" ]]; then
            platforms_json="$(echo "$platforms_json" | jq --arg t "$slack_token" --arg c "$slack_channel" \
              '. + [{"platform": "slack", "token": $t, "channel_id": $c}]')"
            info "Slack configured (channel: ${slack_channel})"
          else
            warn "Slack added without channel ID. Set it later in AGENTS.md."
            platforms_json="$(echo "$platforms_json" | jq --arg t "$slack_token" \
              '. + [{"platform": "slack", "token": $t, "channel_id": "unset"}]')"
          fi
        fi
        ;;

      3) # Discord
        echo ""
        echo "  Discord setup:"
        echo "    1. Create an application at https://discord.com/developers/applications"
        echo "    2. Add a bot, copy the bot token"
        echo "    3. Enable Developer Mode in Discord (Settings → Advanced)"
        echo "    4. Right-click the target channel → Copy Channel ID"
        echo "    Alternative: use a webhook URL (no bot needed for one-way notifications):"
        echo "      Channel Settings → Integrations → Webhooks → New Webhook → Copy URL"
        echo ""

        local discord_mode
        discord_mode="$(prompt_value "Use [b]ot token or [w]ebhook URL?" "b")"
        case "$discord_mode" in
          [wW]*)
            local discord_webhook
            discord_webhook="$(prompt_value "Webhook URL")"
            if [[ -n "$discord_webhook" ]]; then
              platforms_json="$(echo "$platforms_json" | jq --arg w "$discord_webhook" \
                '. + [{"platform": "discord", "mode": "webhook", "webhook_url": $w}]')"
              info "Discord configured (webhook)"
            fi
            ;;
          *)
            local discord_token discord_channel
            discord_token="$(prompt_value "Bot token or 'skip'")"
            if [[ "$discord_token" != "skip" && -n "$discord_token" ]]; then
              discord_channel="$(prompt_value "Channel ID")"
              platforms_json="$(echo "$platforms_json" | jq --arg t "$discord_token" --arg c "${discord_channel:-unset}" \
                '. + [{"platform": "discord", "mode": "bot", "token": $t, "channel_id": $c}]')"
              info "Discord configured (bot, channel: ${discord_channel:-unset})"
            fi
            ;;
        esac
        ;;

      4) # MS Teams
        echo ""
        echo "  Microsoft Teams setup:"
        echo "    1. In your Teams channel: ... menu → Connectors → Incoming Webhook"
        echo "       Or (recommended): create a Power Automate workflow:"
        echo "       - Trigger: 'When a Teams webhook request is received'"
        echo "       - This generates a URL that accepts POST with Adaptive Card JSON"
        echo "    2. Copy the webhook URL"
        echo ""

        local teams_webhook
        teams_webhook="$(prompt_value "Webhook URL or 'skip'")"
        if [[ "$teams_webhook" != "skip" && -n "$teams_webhook" ]]; then
          platforms_json="$(echo "$platforms_json" | jq --arg w "$teams_webhook" \
            '. + [{"platform": "teams", "webhook_url": $w}]')"
          info "MS Teams configured (webhook)"
        else
          warn "Teams not configured. Set webhook URL later in AGENTS.md."
        fi
        ;;

      5|"")
        if [[ "$(echo "$platforms_json" | jq 'length')" -eq 0 ]]; then
          warn "No messaging platform configured. Gate decisions will require manual approval."
          warn "Configure later in AGENTS.md under the nanoclaw section."
        fi
        adding_platforms=false
        continue
        ;;

      *)
        warn "Invalid choice. Enter 1-5."
        continue
        ;;
    esac

    # Offer to add another platform for redundancy
    if $adding_platforms; then
      echo ""
      if ! prompt_yes_no "Add another platform for redundancy?"; then
        adding_platforms=false
      fi
    fi
  done

  # Extract first channel_id for enrollment (backward compat with forge-security.sh)
  local channel_id
  channel_id="$(echo "$platforms_json" | jq -r '.[0].channel_id // "unset"' 2>/dev/null)" || true
  if [[ -z "$channel_id" ]]; then channel_id="unset"; fi

  # Save full platform config for later use by AGENTS.md configuration
  export FORGE_PLATFORMS_JSON="$platforms_json"

  echo ""
  warn "Starting enrollment ceremony..."
  echo "  (This will prompt you to insert/swap your YubiKeys)"
  echo ""

  # Call forge-security.sh enrollment via forge_exec (handles Jinja2 tag stripping)
  local security_script="${FORGE_DIR}/bin/forge-security.sh"
  if [[ -f "$security_script" ]]; then
    export FORGE_SCRIPT_DIR="${FORGE_DIR}/bin"
    forge_exec "$security_script" --enroll --channel "$channel_id" || {
      fail "Enrollment failed. Check the messages above."
      return 1
    }
  else
    fail "forge-security.sh not found."
    return 1
  fi

  info "Step 2 complete."
}

run_step_3() {
  step "3: Configure AGENTS.md"
  echo ""

  local agents_file="${PROJECT_DIR}/AGENTS.md"
  if [[ ! -f "$agents_file" ]]; then
    fail "AGENTS.md not found at ${agents_file}"
    fail "Run this from your project root."
    return 1
  fi

  # Read current values
  local current_enabled current_endpoint current_channel current_skill current_timeout current_retry current_fallback current_auth_provider

  current_enabled="$(grep 'enabled:' "$agents_file" 2>/dev/null | head -1 | sed 's/.*enabled: *//' | tr -d ' ')" || true
  current_endpoint="$(grep 'endpoint:' "$agents_file" 2>/dev/null | head -1 | sed 's/.*endpoint: *//' | tr -d ' ')" || true
  current_channel="$(grep 'channel:' "$agents_file" 2>/dev/null | head -1 | sed 's/.*channel: *//' | tr -d ' \"')" || true
  current_skill="$(grep 'skill_id:' "$agents_file" 2>/dev/null | head -1 | sed 's/.*skill_id: *//' | tr -d ' ')" || true
  current_timeout="$(grep 'timeout_seconds:' "$agents_file" 2>/dev/null | head -1 | sed 's/.*timeout_seconds: *//' | tr -d ' ')" || true
  current_retry="$(grep 'retry_count:' "$agents_file" 2>/dev/null | head -1 | sed 's/.*retry_count: *//' | tr -d ' ')" || true
  current_fallback="$(grep 'fallback:' "$agents_file" 2>/dev/null | head -1 | sed 's/.*fallback: *//' | tr -d ' ')" || true
  current_auth_provider="$(grep 'auth_provider:' "$agents_file" 2>/dev/null | head -1 | sed 's/.*auth_provider: *//' | tr -d ' ')" || true

  # Try to get channel from Step 2 platforms config or enrollment
  local enrolled_channel=""
  if [[ -n "${FORGE_PLATFORMS_JSON:-}" ]]; then
    enrolled_channel="$(echo "$FORGE_PLATFORMS_JSON" | jq -r '.[0].channel_id // empty' 2>/dev/null)" || true
  elif [[ -f "$FORGE_ENROLLED_KEYS" ]]; then
    enrolled_channel="$(jq -r '.channel_id // empty' "$FORGE_ENROLLED_KEYS" 2>/dev/null)" || true
  fi

  echo "Configure NanoClaw settings in AGENTS.md."
  echo "Press Enter to keep the current/default value."
  echo ""

  # Show platforms configured in Step 2
  if [[ -n "${FORGE_PLATFORMS_JSON:-}" ]]; then
    local platform_count
    platform_count="$(echo "$FORGE_PLATFORMS_JSON" | jq 'length' 2>/dev/null)" || true
    if [[ "${platform_count:-0}" -gt 0 ]]; then
      info "Messaging platforms from Step 2:"
      echo "$FORGE_PLATFORMS_JSON" | jq -r '.[] | "    \(.platform): channel \(.channel_id // .webhook_url // "not set")"' 2>/dev/null || true
      echo ""
    fi
  fi

  # Show available auth providers (R5)
  echo "Available authentication providers:"
  local detect_json
  detect_json="$(forge_auth_detect 2>/dev/null)" || true
  if [[ -n "$detect_json" ]]; then
    printf '%s' "$detect_json" | jq -r '.[] | "  \(.provider): \(if .available then "available" else "not available (\(.reason))" end)"' 2>/dev/null || true
  fi
  echo ""

  local new_endpoint new_channel new_skill new_timeout new_retry new_fallback new_auth_provider

  new_auth_provider="$(prompt_value "Auth provider (yubikey/fido2/mobile/auto)" "${current_auth_provider:-auto}")"
  new_endpoint="$(prompt_value "NanoClaw endpoint" "${current_endpoint:-http://localhost:8080}")"

  # Use first platform channel from Step 2 as default, or prompt
  local channel_default="${enrolled_channel:-${current_channel:-}}"
  new_channel="$(prompt_value "Primary channel ID" "$channel_default")"

  new_skill="$(prompt_value "Skill ID" "${current_skill:-forge-gate}")"
  new_timeout="$(prompt_value "Timeout (seconds)" "${current_timeout:-1800}")"
  new_retry="$(prompt_value "Retry count" "${current_retry:-2}")"
  new_fallback="$(prompt_value "Fallback (halt/escalate)" "${current_fallback:-halt}")"

  echo ""
  echo "Will write to AGENTS.md:"
  echo "  enabled:         true"
  echo "  auth_provider:   ${new_auth_provider}"
  echo "  endpoint:        ${new_endpoint}"
  echo "  channel:         ${new_channel}"
  echo "  skill_id:        ${new_skill}"
  echo "  timeout_seconds: ${new_timeout}"
  echo "  retry_count:     ${new_retry}"
  echo "  fallback:        ${new_fallback}"
  if [[ -n "${FORGE_PLATFORMS_JSON:-}" ]]; then
    local pcount
    pcount="$(echo "$FORGE_PLATFORMS_JSON" | jq 'length' 2>/dev/null)" || true
    if [[ "${pcount:-0}" -gt 0 ]]; then
      echo "  platforms:       ${pcount} configured"
    fi
  fi
  echo ""

  if ! prompt_yes_no "Apply these settings?" "y"; then
    warn "Skipped AGENTS.md update."
    return 0
  fi

  # Apply changes using sed — use | as delimiter to handle URLs with /
  sed_inplace "s|enabled: .*false|enabled: true|" "$agents_file"
  sed_inplace "s|auth_provider: .*|auth_provider: ${new_auth_provider}|" "$agents_file"
  sed_inplace "s|endpoint: .*|endpoint: ${new_endpoint}|" "$agents_file"
  sed_inplace "s|channel: .*|channel: \"${new_channel}\"|" "$agents_file"
  sed_inplace "s|skill_id: .*|skill_id: ${new_skill}|" "$agents_file"
  sed_inplace "s|timeout_seconds: .*|timeout_seconds: ${new_timeout}|" "$agents_file"
  sed_inplace "s|retry_count: .*|retry_count: ${new_retry}|" "$agents_file"
  sed_inplace "s|fallback: .*|fallback: ${new_fallback}|" "$agents_file"

  info "AGENTS.md updated."
  info "Step 3 complete."
}

run_step_4() {
  step "4: Test NanoClaw Connectivity"
  echo ""

  local agents_file="${PROJECT_DIR}/AGENTS.md"
  local endpoint
  endpoint="$(grep 'endpoint:' "$agents_file" 2>/dev/null | head -1 | sed 's/.*endpoint: *//' | tr -d ' ')" || true
  endpoint="${endpoint:-http://localhost:8080}"
  local endpoint_clean="${endpoint%/}"

  echo "Testing connection to: ${endpoint_clean}"
  echo ""

  local http_code
  http_code="$(curl -s --connect-timeout 5 -o /dev/null -w '%{http_code}' "${endpoint_clean}/api/health" 2>/dev/null)" || http_code="000"

  case "$http_code" in
    200)
      info "NanoClaw is reachable (HTTP 200)."
      ;;
    000)
      warn "Connection failed — NanoClaw not reachable at ${endpoint_clean}."
      warn "Start NanoClaw and re-run: forge-configure-nanoclaw.sh --step 4"
      warn "Continuing — you can test connectivity later."
      ;;
    *)
      warn "NanoClaw returned HTTP ${http_code} (expected 200)."
      warn "Check your NanoClaw deployment."
      ;;
  esac

  echo ""
  echo "Security status:"
  "${FORGE_DIR}/bin/forge-security.sh" --status 2>/dev/null || warn "Could not retrieve security status."
}

run_step_5() {
  step "5: End-to-End Verification"
  echo ""

  # Detect configured provider
  local agents_file="${PROJECT_DIR}/AGENTS.md"
  local auth_provider="auto"
  if [[ -f "$agents_file" ]]; then
    auth_provider="$(grep 'auth_provider:' "$agents_file" 2>/dev/null | head -1 | sed 's/.*auth_provider: *//' | tr -d ' ')" || true
    auth_provider="${auth_provider:-auto}"
  fi

  # Show provider summary (R5)
  echo "Authentication provider: ${auth_provider}"
  echo ""
  forge_auth_status "$auth_provider" 2>/dev/null || true
  echo ""

  echo "This verifies the full challenge-response round trip."
  echo ""

  if [[ "$auth_provider" == "yubikey" || "$auth_provider" == "auto" ]]; then
    prompt_enter "Confirm STATION key is inserted in desktop USB and press Enter..."
  fi

  # Detect device
  local detect_json=""
  detect_json="$(forge_auth_yubikey_detect 2>/dev/null)" || true
  if [[ -n "$detect_json" ]]; then
    local serial
    serial="$(printf '%s' "$detect_json" | jq -r '.serial')"
    info "YubiKey detected: serial ${serial}"
  fi

  # Generate a test challenge
  local challenge
  challenge="$(openssl rand -hex 32)"
  info "Generated test challenge: ${challenge:0:16}..."

  # Sign with configured provider
  local signature=""
  signature="$(forge_auth_challenge "$auth_provider" "$challenge" 2>/dev/null)" || true
  if [[ -z "$signature" ]]; then
    fail "Challenge-response failed with provider: ${auth_provider}"
    return 1
  fi
  info "Signed: ${signature:0:16}..."

  # Verify by re-signing (deterministic — same challenge should produce same response)
  local verify=""
  verify="$(forge_auth_challenge "$auth_provider" "$challenge" 2>/dev/null)" || true
  if [[ "$signature" == "$verify" ]]; then
    info "Signature verified — deterministic response confirmed."
  else
    fail "Signature mismatch on re-sign. Key may be malfunctioning."
    return 1
  fi

  echo ""
  printf '%b%b%s%b\n' "${BOLD}" "${GREEN}" "=== NanoClaw Configuration Complete ===" "${RESET}"
  echo ""

  # Show summary
  if [[ -f "$FORGE_ENROLLED_KEYS" ]]; then
    local station_id mobile_id channel_id
    station_id="$(jq -r '.keys[] | select(.role=="station") | .key_id' "$FORGE_ENROLLED_KEYS" 2>/dev/null)" || true
    mobile_id="$(jq -r '.keys[] | select(.role=="mobile") | .key_id' "$FORGE_ENROLLED_KEYS" 2>/dev/null)" || true
    channel_id="$(jq -r '.channel_id // "not set"' "$FORGE_ENROLLED_KEYS" 2>/dev/null)" || true
    echo "  Station key:  ${station_id:-unknown}"
    echo "  Mobile key:   ${mobile_id:-unknown}"
    echo "  Channel:      ${channel_id}"
  fi

  local agents_file="${PROJECT_DIR}/AGENTS.md"
  if grep -q 'enabled: true' "$agents_file" 2>/dev/null; then
    echo "  AGENTS.md:    nanoclaw.enabled = true"
  else
    echo "  AGENTS.md:    nanoclaw.enabled = false (not yet configured)"
  fi

  local endpoint
  endpoint="$(grep 'endpoint:' "$agents_file" 2>/dev/null | head -1 | sed 's/.*endpoint: *//' | tr -d ' ')" || true
  local endpoint_clean="${endpoint%/}"
  local http_code
  http_code="$(curl -s --connect-timeout 3 -o /dev/null -w '%{http_code}' "${endpoint_clean}/api/health" 2>/dev/null)" || http_code="000"
  if [[ "$http_code" == "200" ]]; then
    echo "  Endpoint:     ${endpoint_clean} [reachable]"
  else
    echo "  Endpoint:     ${endpoint_clean} [not reachable — start NanoClaw when ready]"
  fi

  echo ""
  echo "Next: start a /implement cycle — gate decisions will route to your phone."
  echo "Guide: docs/nanoclaw-setup.md"
  echo ""

  # Offer to launch NanoClaw if not already reachable
  if [[ "$http_code" != "200" ]]; then
    printf '%b→%b %s' "${YELLOW}" "${RESET}" "Launch NanoClaw now? (y/N): "
    local launch_answer
    read -r launch_answer
    case "$launch_answer" in
      [yY]*)
        local nanoclaw_cmd=""
        if command -v nanoclaw &>/dev/null; then
          nanoclaw_cmd="nanoclaw"
        elif command -v docker &>/dev/null; then
          nanoclaw_cmd="docker"
        fi

        if [[ "$nanoclaw_cmd" == "nanoclaw" ]]; then
          info "Starting NanoClaw..."
          nanoclaw start &
          sleep 2
          local check_code
          check_code="$(curl -s --connect-timeout 3 -o /dev/null -w '%{http_code}' "${endpoint_clean}/api/health" 2>/dev/null)" || check_code="000"
          if [[ "$check_code" == "200" ]]; then
            info "NanoClaw is running at ${endpoint_clean}"
          else
            warn "NanoClaw started but not yet responding. Check logs."
          fi
        elif [[ "$nanoclaw_cmd" == "docker" ]]; then
          echo ""
          echo "Docker detected. Typical NanoClaw launch:"
          echo "  docker compose up -d nanoclaw"
          echo ""
          printf '%b→%b %s' "${YELLOW}" "${RESET}" "Run this command? (y/N): "
          local docker_answer
          read -r docker_answer
          case "$docker_answer" in
            [yY]*)
              docker compose up -d nanoclaw 2>/dev/null || docker-compose up -d nanoclaw 2>/dev/null || {
                warn "Docker compose failed. Start NanoClaw manually."
              }
              ;;
            *) echo "Skipped. Start NanoClaw when ready." ;;
          esac
        else
          echo ""
          echo "NanoClaw binary not found in PATH."
          echo "Start it manually, then verify with:"
          echo "  curl ${endpoint_clean}/api/health"
        fi
        ;;
      *)
        echo "Skipped. Start NanoClaw when ready, then verify with:"
        echo "  curl ${endpoint_clean}/api/health"
        ;;
    esac
  fi
}

# --- Prerequisites check ---
echo ""
printf '%b%s%b\n' "${BOLD}" "FORGE NanoClaw Configuration Wizard" "${RESET}"
echo "====================================="
echo ""
warn "TIP: For a better experience, run /configure-nanoclaw from your AI agent."
warn "This terminal wizard is a fallback for environments without an AI agent."
echo ""

# Verify prerequisites are installed
local_missing=0
for cmd in curl openssl jq ykman; do
  if ! command -v "$cmd" &>/dev/null; then
    local_missing=1
    fail "Required tool not found: ${cmd}"
  fi
done
if [[ "$local_missing" -eq 1 ]]; then
  fail "Prerequisites not installed. Run forge-setup-nanoclaw.sh first."
  exit 1
fi
info "Core prerequisites found (curl, openssl, jq, ykman)."

# Optional: check for libfido2 (FIDO2 provider)
if command -v fido2-token &>/dev/null; then
  info "Optional: libfido2 found (FIDO2 provider available)."
fi

# --- Show status ---
show_status

if $CHECK_ONLY; then
  exit 0
fi

# --- Run steps ---
for step_num in 1 2 3 4 5; do
  if [[ "$step_num" -lt "$START_STEP" ]]; then
    continue
  fi

  if "check_step_${step_num}" 2>/dev/null; then
    labels=("Program YubiKeys" "Enroll keys" "Configure AGENTS.md" "Test connectivity" "End-to-end verification")
    label="${labels[$((step_num-1))]}"
    echo ""
    info "Step ${step_num} (${label}) appears complete."
    if ! prompt_yes_no "Run it anyway?"; then
      continue
    fi
  fi

  "run_step_${step_num}" || {
    echo ""
    if prompt_yes_no "Step ${step_num} had issues. Continue to next step?"; then
      continue
    else
      warn "Wizard paused. Resume with: forge-configure-nanoclaw.sh --step ${step_num}"
      exit 1
    fi
  }
done
