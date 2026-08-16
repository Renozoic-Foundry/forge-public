#!/usr/bin/env bash
# FORGE Specless Commit Guard — PreToolUse hook (Spec 257; schema migrated Spec 499)
# Blocks `git commit` Bash calls when no active spec or close marker exists.
#
# Behavior:
#   - Bash call is NOT git commit  → allow (fast exit)
#   - implementing.json exists     → allow (active /implement)
#   - active-close exists          → allow (active /close)
#   - Neither marker present       → block (specless commit attempt)
#   - jq missing                   → allow (fail-open — same as check-role-permissions.sh)
#
# Schema (Spec 499): blocks via the documented PreToolUse
# hookSpecificOutput.permissionDecision="deny" form. The prior top-level
# {"decision":"block"} was honored only via undocumented backward-compat (verified
# 2026-06-24), not the documented PreToolUse contract. When blocked, deny is a HARD
# BLOCK — it raises no in-session permission dialog; the REASON below lists the
# actionable ways to proceed (re-run after /implement|/close, or run it in the terminal).

# Read tool input from stdin (Claude Code passes JSON with tool_input.command)
INPUT=$(cat)

# Fast path: if jq is not available, fail-open
if ! command -v jq >/dev/null 2>&1; then
  # Try grep fallback for git commit detection
  if ! echo "$INPUT" | grep -qE '"command".*git[[:space:]]+commit'; then
    exit 0
  fi
  # Can't reliably parse without jq — fail-open
  exit 0
fi

# Extract the Bash command from stdin JSON
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
if [ -z "$COMMAND" ]; then
  exit 0
fi

# Only intercept git commit commands at command position (Spec 300; detection extracted
# to a shared helper in Spec 498). The command-position detection — heredoc/newline
# normalization, quote-stripping, git global-option tolerance, the command-position
# anchors, and the `commit`-vs-`commit-tree` trailing anchor — now lives ONCE in
# lib/git-command-detect.sh, sourced by BOTH this guard and check-push-guard.sh (not
# copy-pasted across two guards × two surfaces — the CI-445 drift class). See that file
# for the full grammar. This guard and the push guard differ only in matcher (commit vs
# push) and decision (deny vs ask).
GUARD_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")/lib" 2>/dev/null && pwd)/git-command-detect.sh"
if [ ! -f "$GUARD_LIB" ]; then
  # Helper missing — fail-open (consistent with the jq-missing posture above).
  exit 0
fi
# shellcheck source=lib/git-command-detect.sh
. "$GUARD_LIB"

if ! forge_git_subcommand_at_command_position "commit" "$COMMAND"; then
  exit 0
fi

# Spec 476: resolve markers against the COMMITTING worktree, not the hook's CWD.
# PreToolUse hooks fire in the parent session's working directory, so a `git
# commit` run inside a worktree (via `git -C <wt> ...`, a leading `cd <wt> &&`,
# or a sub-agent whose session cwd IS the worktree) must find ITS OWN markers.
# Multi-signal detection; any uncertainty falls back to "." (the original
# main-CWD behavior), which fails TOWARD the block (Spec 476 Req 2/3).
abs_git_common_dir() {
  # $1 = a directory inside a working tree; prints the ABSOLUTE git common dir
  # (shared across linked worktrees) or nothing.
  local gcd
  gcd=$(git -C "$1" rev-parse --git-common-dir 2>/dev/null) || return 0
  [ -z "$gcd" ] && return 0
  ( cd "$1" && cd "$gcd" 2>/dev/null && pwd )
}

PAYLOAD_CWD=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)

COMMIT_DIR=""
# 1. Explicit `git -C <path>` (git's own working-dir override) — highest priority.
if printf '%s' "$COMMAND" | grep -qE 'git[[:space:]]+-C[[:space:]]'; then
  COMMIT_DIR=$(printf '%s' "$COMMAND" | sed -nE 's/.*git[[:space:]]+-C[[:space:]]+("([^"]+)"|'"'"'([^'"'"']+)'"'"'|([^[:space:]]+)).*/\2\3\4/p' | head -1)
fi
# 2. Leading `cd <path> &&` / `cd <path> ;`
if [ -z "$COMMIT_DIR" ] && printf '%s' "$COMMAND" | grep -qE '^[[:space:]]*cd[[:space:]]'; then
  COMMIT_DIR=$(printf '%s' "$COMMAND" | sed -nE 's/^[[:space:]]*cd[[:space:]]+("([^"]+)"|'"'"'([^'"'"']+)'"'"'|([^[:space:]&;|]+)).*/\2\3\4/p' | head -1)
fi
# 3. Payload cwd (session working dir for the intercepted Bash tool call).
if [ -z "$COMMIT_DIR" ] && [ -n "$PAYLOAD_CWD" ]; then
  COMMIT_DIR="$PAYLOAD_CWD"
fi

# Trust the resolved dir ONLY when it is a working tree of THIS repository (same
# git common dir) — rejects a marker planted at an unrelated path injected via a
# crafted `cd`/`-C` (the agent cannot self-authorize a bypass; Spec 257 property).
STATE_ROOT="."
if [ -n "$COMMIT_DIR" ] && [ -d "$COMMIT_DIR" ]; then
  WT_TOP=$(git -C "$COMMIT_DIR" rev-parse --show-toplevel 2>/dev/null || true)
  if [ -n "$WT_TOP" ]; then
    hook_common=$(abs_git_common_dir ".")
    wt_common=$(abs_git_common_dir "$WT_TOP")
    if [ -n "$wt_common" ] && [ "$wt_common" = "$hook_common" ]; then
      STATE_ROOT="$WT_TOP"
    fi
  fi
fi

# Check for active spec marker (set by /implement) in the committing worktree
if [ -f "$STATE_ROOT/.forge/state/implementing.json" ]; then
  exit 0
fi

# Check for active close marker (set by /close) in the committing worktree
if [ -f "$STATE_ROOT/.forge/state/active-close" ]; then
  exit 0
fi

# Spec 421: session-log-artifact auto-allow.
# Auto-allow a commit when EVERY staged path is a recognized session-log
# artifact under docs/sessions/ — the dated log + its .json sidecar plus the
# named append-only logs. Staged paths come from git state (git diff --cached),
# NOT from any agent-writable file, so Spec 257's "agent cannot self-authorize
# a bypass" property holds for every other path (Spec 421 Req 6).
#   - Empty staged set (e.g. `git commit -am`, whose autostage runs AFTER this
#     PreToolUse hook) → fall through to the block. Never vacuously auto-allow.
#   - git error (not a repo, git missing, corrupt index) → fall through to the
#     block. A git failure is never read as an auto-allow.
#   - registry.md is intentionally NOT on the list (it is the ephemeral
#     "do not commit" multi-tab coordination file).
# Each path is matched individually against an anchored (^...$) regex so a path
# segment can never satisfy the pattern by appearing inside a longer string.
# Spec 676 (EA-005): forge.paths-aware session-artifact exemption, security-hardened
# (Spec 676 review). NO dynamic regex is built from config: a configured value containing ERE
# metacharacters (|, (, ), .*) must not be able to widen the allow surface — the guard's
# self-authorization property. Directory prefixes are compared LITERALLY (quoted string
# equality); only the artifact BASENAME is a fixed, config-independent anchored regex. The
# allowed-dir list is a bash array iterated quoted (no word splitting, no glob expansion), so a
# configured path with spaces or glob characters is handled as one literal string. Config is
# resolved in an isolated subshell with PROJECT_DIR bound to the committing worktree
# (STATE_ROOT), so forge_path validates against it rather than the hook's cwd. The classic
# docs/sessions dir is always allowed; resolution fails closed to docs/sessions alone.
SESSION_ARTIFACT_BASENAME_RE='^([0-9]{4}-[0-9]{2}-[0-9]{2}-[0-9]+\.(md|json)|error-log\.md|insights-log\.md|scratchpad\.md|watchlist\.md|context-snapshot\.md|pattern-analysis\.md|evolve-state\.md|activity-log\.jsonl|signals\.md)$'
SESSION_DIRS=("docs/sessions")
if [ -f "$STATE_ROOT/.forge/lib/config.sh" ]; then
  _cfg_sessions="$(
    PROJECT_DIR="$STATE_ROOT"
    # shellcheck disable=SC1090
    . "$STATE_ROOT/.forge/lib/config.sh" 2>/dev/null \
      && forge_config_load "$STATE_ROOT/AGENTS.md" 2>/dev/null \
      && forge_path sessions 2>/dev/null
  )"
  _cfg_sessions="${_cfg_sessions%/}"
  if [ -n "$_cfg_sessions" ] && [ "$_cfg_sessions" != "docs/sessions" ]; then
    SESSION_DIRS+=("$_cfg_sessions")
  fi
fi
if STAGED=$(git -C "$STATE_ROOT" diff --cached --name-only 2>/dev/null) && [ -n "$STAGED" ]; then
  all_session_artifacts=1
  while IFS= read -r staged_path; do
    [ -z "$staged_path" ] && continue
    _base="${staged_path##*/}"
    _dir="${staged_path%/*}"
    # A top-level path (no slash) has _dir == staged_path and can never be a session dir.
    if [ "$_dir" = "$staged_path" ]; then all_session_artifacts=0; break; fi
    # Basename must match the fixed, config-independent artifact allowlist.
    if ! printf '%s\n' "$_base" | grep -qE "$SESSION_ARTIFACT_BASENAME_RE"; then
      all_session_artifacts=0; break
    fi
    # Directory prefix must LITERALLY equal an allowed session dir (no regex, no globbing).
    _dir_ok=0
    for _d in "${SESSION_DIRS[@]}"; do
      if [ "$_dir" = "$_d" ]; then _dir_ok=1; break; fi
    done
    if [ "$_dir_ok" -eq 0 ]; then all_session_artifacts=0; break; fi
  done <<< "$STAGED"
  if [ "$all_session_artifacts" -eq 1 ]; then
    exit 0
  fi
fi

# No marker found and the staged paths are not all session-log artifacts — block.
# Offer actionable alternatives (the prompt IS this denied tool call, so "approve
# at the prompt" is not actionable — Spec 421). Build the decision block with
# `jq -n` so the paste-able command cannot break the JSON.
REASON="COMMIT GUARD (Spec 257): No active spec or /close in progress, and the staged paths are not all session-log artifacts. "
REASON+="To proceed, do one of: "
REASON+="(1) re-run this commit after /implement <spec-number> or /close <spec-number> sets the active marker; "
REASON+="(2) run it yourself in the terminal: git commit -m \"<your message>\"; "
REASON+="(3) stage only session-log artifacts under docs/sessions/ (the dated YYYY-MM-DD-NNN log + its .json sidecar, error-log.md, insights-log.md, etc.). "
REASON+="TIMING (Spec 536): this guard is a PreToolUse hook — it inspects marker and staged state BEFORE your command runs. A marker write or git add chained in the SAME Bash call is invisible to it: use TWO separate calls (write the marker / stage first; then run git commit alone)."

jq -nc --arg r "$REASON" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
exit 0
