#!/usr/bin/env bash
# FORGE Push Authorization Guard — PreToolUse hook (Spec 498; schema per Spec 499)
# Forces the operator's permission prompt for every `git push` Bash call by emitting the
# documented PreToolUse hookSpecificOutput.permissionDecision="ask".
#
# WHY `ask` (NOT `deny`): this is the deferred-close chaining backstop. Chaining
# (implement -> implement_next, no intervening /close) removes the per-spec human
# checkpoint, so the push gate keeps the close/push human-authorization boundary (the
# EA-025/026/027 self-authorization failures) from re-opening at L3/L4. Spec 499 verified
# against current Claude Code docs: `ask` PROMPTS the operator even under
# bypassPermissions; `deny` is a HARD BLOCK with NO prompt; the legacy top-level
# {"decision":"block"} is a PreToolUse no-op. The push guard WANTS an in-session approval,
# so it uses `ask` — the ONE place it differs from check-commit-guard.sh (which uses `deny`).
#
# PROVENANCE: the harness-issued permission prompt IS the operator-provenance primitive.
# There is NO on-disk sign-off marker and NO nonce — nothing forgeable on disk. The agent
# cannot self-authorize the push; only the operator approving at the prompt can. The guard
# reads/trusts no marker, so writing .forge/state/ files or placing a "sign-off" string in
# assistant-visible content cannot bypass it (Spec 498 AC2).
#
# DETECTION: command-position detection is the SHARED helper (lib/git-command-detect.sh) —
# the SAME logic check-commit-guard.sh uses (heredoc/quote-stripping, global-option
# tolerance). The two guards differ only in matcher (push vs commit) and decision (ask vs
# deny). No copy-paste (Spec 498 Req 1 / CTO R1).
#
# TRUST CEILING (ADR-453 / Spec 498 §6.1, honest): this hook lives in agent-editable
# .claude/settings.json and is bypassable at L3/L4 (an agent at L3 could remove the hook
# entry). Hard enforcement rests on the agent-immutable managed-settings.json trust root
# (server-managed settings — Claude.ai admin console, InfoSec-gated — the per-user path is
# non-viable). Until that lands the L3/L4 guarantee is "designed, not enforced" and
# deferred-close chaining stays L1/L2-gated. The .claude/settings.json registration is
# defense-in-depth for L0–L2 / unmanaged machines.
#
# Behavior:
#   - Bash call is NOT git push at command position → allow (fast exit, defer to normal flow)
#   - git push at command position                  → ask (operator approves at the prompt)
#   - jq missing                                    → allow (fail-open — guard-family posture)
#   - detection helper missing                      → allow (fail-open — same posture)

# Read tool input from stdin (Claude Code passes JSON with tool_input.command).
INPUT=$(cat)

# Fast path: fail-open without jq (matches check-commit-guard.sh / check-role-permissions.sh).
if ! command -v jq >/dev/null 2>&1; then
  # Without jq we cannot reliably parse the command — fail-open regardless.
  exit 0
fi

# Extract the Bash command from stdin JSON.
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
if [ -z "$COMMAND" ]; then
  exit 0
fi

# Shared command-position detection (Spec 498 Req 1 / CTO R1 — one sourced helper, not
# copy-pasted). Fail-open if the helper is missing (consistent with the jq-missing posture).
GUARD_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")/lib" 2>/dev/null && pwd)/git-command-detect.sh"
if [ ! -f "$GUARD_LIB" ]; then
  exit 0
fi
# shellcheck source=lib/git-command-detect.sh
. "$GUARD_LIB"

# Only intercept `git push` at command position. Non-push Bash passes through.
if ! forge_git_subcommand_at_command_position "push" "$COMMAND"; then
  exit 0
fi

# git push at command position — force the operator approval prompt (permissionDecision:ask).
# No on-disk marker is read or trusted; the permission prompt is the operator-provenance
# primitive. Build the JSON with `jq -n` so the reason text cannot break the payload.
REASON="PUSH GATE (Spec 498): git push requires your approval at this prompt. "
REASON+="Deferred-close chaining removes the per-spec human checkpoint, so the push is gated "
REASON+="here as the backstop for the close/push human-authorization boundary (EA-025/026/027). "
REASON+="Approve to push, or decline to cancel. No on-disk sign-off can bypass this — only your "
REASON+="approval at this prompt authorizes the push."

jq -nc --arg r "$REASON" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"ask",permissionDecisionReason:$r}}'
exit 0
