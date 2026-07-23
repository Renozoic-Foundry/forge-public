#!/usr/bin/env bash
# FORGE Validator Git-Command Guard — PreToolUse hook (Spec 547)
# Runtime enforcement, at the Bash layer, of the validator side-effect doctrine codified
# as prose by Spec 536 (validator.md / /close dispatch prompt): a read-only role (e.g. the
# validator subagent) must never execute an authorization-gated git command class. Spec 536
# closed prose-only; check-role-permissions.sh already gates Write/Edit/NotebookEdit while
# `.forge/state/active-role.json` declares a read-only role, but a validator could still run
# a gated git class through Bash (SIG-520-02's original vector). This hook closes that gap
# on the SAME marker + SAME staleness bound already proven by check-role-permissions.sh.
#
# Gated classes (Spec 547 Scope): git push, git reset, git restore, git clean,
# git checkout -- <path>, git branch -D. Detection reuses the shared command-position
# helper (lib/git-command-detect.sh) for the plain-subcommand classes (push/reset/
# restore/clean) — the SAME grammar check-commit-guard.sh / check-push-guard.sh use, not
# a copy-pasted regex. `checkout --` and `branch -D` need an extra flag/token check beyond
# subcommand position, so those two add a coarse grep on top of the position match; per the
# established authority-guard posture (see check-authority-guard.sh's verb-class comment)
# a coarse over-block on these two fails TOWARD the safe direction, never toward a bypass.
#
# Staleness bound (Spec 547 AC2 / scope note "MUST resolve or bound staleness first"): this
# hook reuses check-role-permissions.sh's proven >30-minute freshness window verbatim — no
# new staleness mechanism is introduced. A marker older than 30 minutes allows (same
# rationale: the orchestrator may have crashed without clearing it) so a stale leftover
# marker cannot brick an operator's own terminal session. The underlying active-role.json
# timezone/staleness DEFECT noted at Spec 536 is NOT fixed here — out of scope (Spec 547
# Scope) — this hook only bounds its blast radius using the existing, shipped mechanism.
#
# Behavior:
#   - No state file / empty / jq missing        → allow (fail-open, matches check-role-permissions.sh)
#   - read_only: false / absent                 → allow
#   - Stale marker (>30 min)                    → allow (same bound as check-role-permissions.sh)
#   - read_only: true, fresh, gated git class    → deny, doctrine-citing message
#   - read_only: true, fresh, non-gated command  → allow
#
# Schema (Spec 499): denies via the documented PreToolUse
# hookSpecificOutput.permissionDecision="deny" form.

STATE_FILE=".forge/state/active-role.json"

# Fast path: no state file means no restrictions.
if [ ! -f "$STATE_FILE" ]; then
  exit 0
fi

ROLE_DATA=$(cat "$STATE_FILE" 2>/dev/null)
if [ -z "$ROLE_DATA" ]; then
  exit 0
fi

if ! command -v jq >/dev/null 2>&1; then
  exit 0
fi

READ_ONLY=$(echo "$ROLE_DATA" | jq -r '.read_only // false' 2>/dev/null)
ROLE_NAME=$(echo "$ROLE_DATA" | jq -r '.role // "unknown"' 2>/dev/null)
STARTED=$(echo "$ROLE_DATA" | jq -r '.started // empty' 2>/dev/null)

# Stale state detection (>30 minutes = 1800 seconds) — identical bound to
# check-role-permissions.sh (Spec 547 AC2).
if [ -n "$STARTED" ]; then
  STARTED_TS=$(date -d "$STARTED" +%s 2>/dev/null || \
               date -jf '%Y-%m-%dT%H:%M:%S' "${STARTED%%Z}" +%s 2>/dev/null || \
               echo 0)
  NOW_TS=$(date +%s)
  ELAPSED=$(( NOW_TS - STARTED_TS ))
  if [ "$ELAPSED" -gt 1800 ]; then
    exit 0
  fi
fi

if [ "$READ_ONLY" != "true" ]; then
  exit 0
fi

# Read tool input from stdin (Claude Code passes JSON with tool_input.command).
INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
if [ -z "$COMMAND" ]; then
  exit 0
fi

GUARD_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")/lib" 2>/dev/null && pwd)/git-command-detect.sh"
if [ ! -f "$GUARD_LIB" ]; then
  # Helper missing — fail-open (consistent with the jq-missing posture above).
  exit 0
fi
# shellcheck source=lib/git-command-detect.sh
. "$GUARD_LIB"

GATED_CLASS=""
if forge_git_subcommand_at_command_position "push" "$COMMAND"; then
  GATED_CLASS="git push"
elif forge_git_subcommand_at_command_position "reset" "$COMMAND"; then
  GATED_CLASS="git reset"
elif forge_git_subcommand_at_command_position "restore" "$COMMAND"; then
  GATED_CLASS="git restore"
elif forge_git_subcommand_at_command_position "clean" "$COMMAND"; then
  GATED_CLASS="git clean"
elif forge_git_subcommand_at_command_position "checkout" "$COMMAND" && \
     printf '%s' "$COMMAND" | grep -qE -- '--'; then
  GATED_CLASS="git checkout --"
elif forge_git_subcommand_at_command_position "branch" "$COMMAND" && \
     printf '%s' "$COMMAND" | grep -qE -- '(^|[[:space:]])-D([[:space:]]|$)'; then
  GATED_CLASS="git branch -D"
fi

if [ -z "$GATED_CLASS" ]; then
  exit 0
fi

REASON="VALIDATOR GIT GUARD (Spec 547): '${GATED_CLASS}' is an authorization-gated git class. "
REASON+="The active role '${ROLE_NAME}' is marked read-only (.forge/state/active-role.json), and "
REASON+="the Spec 536 validator doctrine forbids a read-only role from running gated git commands "
REASON+="(git checkout --, reset, restore, clean, branch -D, push) — the read-only contract is "
REASON+="verify-only, no side effects. If this is a legitimate operator action, run it yourself in "
REASON+="the terminal, or clear the role marker via the normal /close role-exit flow first."

jq -nc --arg r "$REASON" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
exit 0
