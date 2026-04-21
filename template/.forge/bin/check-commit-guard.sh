#!/usr/bin/env bash
# FORGE Specless Commit Guard — PreToolUse hook (Spec 257)
# Blocks `git commit` Bash calls when no active spec or close marker exists.
#
# Behavior:
#   - Bash call is NOT git commit  → allow (fast exit)
#   - implementing.json exists     → allow (active /implement)
#   - active-close exists          → allow (active /close)
#   - Neither marker present       → block (specless commit attempt)
#   - jq missing                   → allow (fail-open — same as check-role-permissions.sh)
#
# The only bypass when blocked is the Claude Code permission prompt — the operator
# must explicitly approve. The agent cannot self-authorize bypass.

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

# Only intercept git commit commands at command position (Spec 300).
# Preprocess:
#   1. Normalize newlines to spaces so the `^` anchor cannot match inside
#      heredoc bodies whose lines literally start with `git commit` (docs,
#      tutorials, session logs that quote a commit command).
#   2. Strip quoted substrings (both "…" and '…') so shell separators that
#      appear INSIDE quoted arguments (e.g. `echo "use ; git commit"`) do
#      not fake a command-position anchor. Non-greedy, single-level (nested
#      or escaped quotes are a known limit — see docs/process-kit/commit-
#      guard-rationale.md).
# Match anchors (command-position forms of `git commit`):
#   - start of (normalized) string, or after a shell separator `;`, `&`, `|`, `(`, `)`, `{`, `}`, backtick
#   - after a command-wrapping keyword: xargs, sudo, env, time, nohup, exec, then, else, do
#   - after one or more env-var assignments (e.g. `GIT_AUTHOR_DATE=… git commit`)
# Trailing anchor: whitespace or end-of-string (so `git commit-tree` doesn't match).
NORMALIZED=$(echo "$COMMAND" | tr '\n' ' ')
STRIPPED=$(echo "$NORMALIZED" | sed -E 's/"[^"]*"//g; s/'"'"'[^'"'"']*'"'"'//g')
GUARD_RE='(^|[;|&()\{\}`]|(^|[[:space:]])(xargs|sudo|env|time|nohup|exec|then|else|do)[[:space:]])[[:space:]]*([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+)*git[[:space:]]+commit([[:space:];|&()\{\}]|$)'
if ! echo "$STRIPPED" | grep -qE "$GUARD_RE"; then
  exit 0
fi

# Check for active spec marker (set by /implement)
if [ -f ".forge/state/implementing.json" ]; then
  exit 0
fi

# Check for active close marker (set by /close)
if [ -f ".forge/state/active-close" ]; then
  exit 0
fi

# No marker found — block the commit
REASON="COMMIT GUARD (Spec 257): No active spec or /close in progress. "
REASON+="Run /implement <spec-number> before committing. "
REASON+="If this is a legitimate non-spec commit (session log, /forge stoke), approve this tool call to proceed."

echo "{\"decision\":\"block\",\"reason\":\"${REASON}\"}"
exit 0
