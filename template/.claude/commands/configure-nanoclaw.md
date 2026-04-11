---
name: configure-nanoclaw
description: "Configure NanoClaw hardware key enrollment and messaging"
model_tier: sonnet
workflow_stage: configuration
---
# Framework: FORGE
Configure NanoClaw — AI-orchestrated hardware key enrollment and messaging platform setup.

If $ARGUMENTS is `?` or `help`:
  Print:
  ```
  /configure-nanoclaw — Set up NanoClaw gate authentication and messaging.
  Usage: /configure-nanoclaw [--step N]
  Arguments:
    --step N  — Jump to a specific step (1-5)
  Behavior:
    - Detects connected hardware keys and available auth providers
    - Programs YubiKey slots (with safety pre-flight and irreversibility warnings)
    - Enrolls keys with FORGE
    - Configures messaging platform(s) for gate decisions
    - Updates AGENTS.md with final configuration
    - All operations run behind the scenes — user interaction stays in this conversation
  Prerequisite: run forge-setup-nanoclaw.sh first to install ykman and dependencies.
  ```
  Stop — do not execute any further steps.

---

**Principle**: All user interaction happens in this conversation. Never ask the user to open a terminal or run a script directly. Run CLI commands behind the scenes using the Bash tool and present results here.

---

## Step 1: Detect Devices and Providers

1. Run: `bash .forge/bin/forge-security.sh --detect --json`
   - If the command fails (exit non-zero or missing), check if `.forge/bin/forge-security.sh` exists. If not, tell the user to run `forge-setup-nanoclaw.sh` first.
   - Make sure Yubico tools are in PATH by prepending known install directories:
     ```bash
     export PATH="/c/Program Files/Yubico/YubiKey Manager CLI:$PATH"
     ```

2. Parse the JSON result. Present a formatted summary:

   ```
   ## NanoClaw Configuration

   ### Connected Devices
   | # | Device | Serial | OTP | Slot 2 |
   |---|--------|--------|-----|--------|
   | 1 | YubiKey 5 NFC | 15194777 | enabled | programmed |
   | 2 | YubiKey 5C NFC | 16769179 | enabled | programmed |

   ### Available Providers
   - yubikey: available (2 devices)
   - fido2: not available (fido2-token not installed)
   - mobile: available (via NanoClaw)

   ### Enrollment Status
   - Not enrolled / Enrolled (station: YK-15194777, mobile: YK-16769179)
   ```

3. If no devices are detected and ykman is not installed, suggest running prerequisites first.

4. If devices are detected but OTP is "not_available" on all of them, explain that these models don't support HMAC-SHA1 and suggest the FIDO2 or mobile provider instead.

5. Always present **all 5 steps** with a status indicator based on detection results. Use checkmarks for steps that appear complete, arrows for the recommended next step, and dashes for pending steps. Example:

   ```
   ### Steps
   | # | Step | Status |
   |---|------|--------|
   | 1 | Detect devices & providers | ✓ Complete (2 keys found) |
   | 2 | Program YubiKey slots | ✓ Both keys responding — re-run to reprogram |
   | 3 | Enroll keys with FORGE | → Not enrolled |
   | 4 | Configure messaging platform | — Pending |
   | 5 | Update AGENTS.md | — Pending |

   Enter a step number to start from, or 'all' to run through everything:
   ```

   Status logic:
   - Step 1: Always "✓ Complete" (just ran)
   - Step 2: "✓" if both keys slot 2 responds, "→" if any key needs programming
   - Step 3: "✓" if enrolled, "→" if not enrolled and step 2 is done
   - Step 4: "✓" if AGENTS.md has messaging configured, otherwise "—" or "→"
   - Step 5: "✓" if AGENTS.md has `enabled: true`, otherwise "—" or "→"
   - Mark the first incomplete step with "→" to suggest where to start
   - Completed steps can still be selected (for re-enrollment, reprogramming, etc.)

---

## Step 2: Program YubiKeys (Safety Pre-flight)

For each key that needs programming:

1. Run: `bash .forge/bin/forge-security.sh --slot-audit --device SERIAL --json`

2. Present the slot audit results:
   ```
   ### Key: YubiKey 5 NFC (15194777)
   - Slot 1: programmed (FORGE never modifies slot 1)
   - Slot 2: empty
   ```

3. **If slot 2 is already responding to challenges**: Tell the user:
   ```
   Slot 2 is already programmed with HMAC-SHA1 challenge-response. No action needed.
   ```
   Ask if they want to reprogram anyway (with irreversibility warning) or skip.

4. **If slot 2 is empty**: Ask for confirmation:
   ```
   Slot 2 is empty. Ready to program HMAC-SHA1 challenge-response.
   This will generate a random secret and store it in the YubiKey hardware.
   Proceed? (yes/no)
   ```

5. **If slot 2 is programmed with something else** (not challenge-response): Show irreversibility warning:
   ```
   ⚠️ IRREVERSIBLE OPERATION
   Slot 2 currently contains: [type]
   Programming will PERMANENTLY DESTROY the existing secret.
   YubiKey secrets are write-only — once overwritten, the previous secret cannot be recovered.

   Are you sure you want to overwrite slot 2? (yes/no — default: no)
   ```
   Only proceed on explicit "yes".

6. On confirmation, run:
   ```bash
   bash .forge/bin/forge-security.sh --program --device SERIAL --slot 2 --save-secret ~/.forge/secrets/SERIAL-slot2.key --json
   ```

7. Present the result:
   ```
   ✓ Slot 2 programmed on YubiKey 15194777
     Generated secret: bd86e53d3507ba65374cf60a61bd48220d8d8dc3
     Saved to: ~/.forge/secrets/15194777-slot2.key (mode 600)

     ⚠️ This file is the ONLY way to program a replacement key with the same secret.
     Store it securely (e.g., encrypted vault, printed in a safe).
   ```

8. Repeat for the second key.

---

## Step 3: Enroll Keys with FORGE

1. If enrollment already exists (from detect), show current enrollment and ask if re-enrollment is needed.

2. Determine which key is station (desktop USB) and which is mobile (keychain). Ask the user:
   ```
   Assign key roles:
   - YubiKey 5 NFC (15194777) — Station (desktop USB) or Mobile (keychain)?
   - YubiKey 5C NFC (16769179) — will be assigned the other role

   Which key is your STATION key (stays plugged into your desktop)?
   Enter serial number or 1/2:
   ```

3. Run enrollment:
   ```bash
   bash .forge/bin/forge-security.sh --enroll --station STATION_SERIAL --mobile MOBILE_SERIAL --json
   ```
   Note: channel_id is set in Step 4.

4. Present result:
   ```
   ✓ Keys enrolled with FORGE
     Station: YK-15194777 (YubiKey 5 NFC)
     Mobile:  YK-16769179 (YubiKey 5C NFC)
   ```

---

## Step 4: Configure Messaging Platform

1. Present the platform options:
   ```
   ### Messaging Platform for Gate Decisions

   NanoClaw sends approve/reject decisions to your messaging platform.
   You can configure one or more platforms for redundancy.

   | # | Platform | Features | Setup |
   |---|----------|----------|-------|
   | 1 | Telegram | Inline approve/reject buttons | Easy — @BotFather |
   | 2 | Slack | Block Kit buttons | Medium — api.slack.com |
   | 3 | Discord | Message components / webhooks | Medium — developer portal |
   | 4 | MS Teams | Adaptive Cards | High — Power Automate |
   | 5 | Skip | Configure later in AGENTS.md | — |

   Which platform(s)? (enter numbers, e.g. "1" or "1,2" for redundancy)
   ```

2. For each selected platform, walk through setup **in the conversation**:

   **Telegram:**
   - "Do you already have a Telegram bot token? If not, here's how to create one:"
   - Provide step-by-step: Open Telegram → search @BotFather → /newbot → follow prompts → copy token
   - Once user provides token, run behind the scenes:
     ```bash
     curl -s "https://api.telegram.org/bot<TOKEN>/getUpdates" | jq '.result[-1].message.chat.id'
     ```
   - If chat ID found: "I found your chat ID: 123456789. Is this correct?"
   - If not found: "No messages found. Please send /start to your bot in Telegram, then tell me to try again."

   **Slack:**
   - Walk through: Create app at api.slack.com → Bot scopes (chat:write, im:write) → Install → Copy xoxb- token
   - Ask for channel ID (explain: right-click channel → View details → ID at bottom)

   **Discord:**
   - Ask: bot or webhook?
   - Bot: Create app → Add bot → Copy token → Provide channel ID
   - Webhook: Channel Settings → Integrations → Webhooks → Copy URL

   **MS Teams:**
   - Walk through Power Automate workflow creation
   - Ask for webhook URL

3. After all platforms configured, ask: "Add another platform for redundancy? (yes/no)"

4. Store the collected configuration for Step 5.

---

## Step 5: Update AGENTS.md

1. Read the current AGENTS.md nanoclaw section.

2. Present the proposed changes:
   ```
   ### Proposed AGENTS.md Configuration

   nanoclaw:
     enabled: true
     auth_provider: yubikey
     endpoint: http://localhost:8080
     channel: "123456789"
     skill_id: forge-gate
     timeout_seconds: 1800
     retry_count: 2
     fallback: halt
   ```

3. Ask: "Apply these settings to AGENTS.md? (yes/no)"

4. On confirmation, use the Edit tool to update AGENTS.md.

5. If the user had configured messaging platforms, also update the enrollment file with the channel ID:
   ```bash
   bash .forge/bin/forge-security.sh --enroll --station SERIAL --mobile SERIAL --channel CHANNEL_ID --json
   ```

---

## Summary

After all steps, present a final summary:

```
## NanoClaw Configuration Complete

| Component | Status |
|-----------|--------|
| Station key | YK-15194777 — enrolled, slot 2 programmed |
| Mobile key | YK-16769179 — enrolled, slot 2 programmed |
| Auth provider | yubikey |
| Messaging | Telegram (chat ID: 123456789) |
| AGENTS.md | enabled: true |
| Secret backup | ~/.forge/secrets/ (2 files) |

### Next Steps
- Start NanoClaw: `nanoclaw start` or `docker compose up -d nanoclaw`
- Test connectivity: run `/implement` on any spec — gate decisions will route to your phone
- Guide: docs/nanoclaw-setup.md
```

---

## Error Handling

Throughout all steps:
- If a command fails, show the error to the user with explanation and recovery options
- If a device is disconnected mid-flow, detect it and ask the user to reconnect
- If multiple keys are detected but --device wasn't used, list them and ask which to use
- Never proceed with destructive operations (programming) without explicit user confirmation
- If the user says "skip" at any step, move to the next step
- If the user says "stop" or "cancel", halt and report what was completed
