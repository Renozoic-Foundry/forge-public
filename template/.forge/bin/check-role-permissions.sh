#!/usr/bin/env bash
# FORGE Role Permission Check — PreToolUse hook
# Blocks Write/Edit/NotebookEdit when the active role is read-only.
#
# Behavior:
#   - No state file          → allow (normal development)
#   - read_only: false       → allow
#   - read_only: true        → block with role name in reason
#   - Stale (>30 min)        → allow (orchestrator may have crashed)
#   - jq missing / malformed → allow (fail-open)

STATE_FILE=".forge/state/active-role.json"

# Fast path: no state file means no restrictions
if [ ! -f "$STATE_FILE" ]; then
  echo '{"decision":"allow"}'
  exit 0
fi

# Read the state file
ROLE_DATA=$(cat "$STATE_FILE" 2>/dev/null)
if [ -z "$ROLE_DATA" ]; then
  echo '{"decision":"allow"}'
  exit 0
fi

# Check if jq is available
if ! command -v jq >/dev/null 2>&1; then
  echo '{"decision":"allow"}'
  exit 0
fi

# Parse fields
READ_ONLY=$(echo "$ROLE_DATA" | jq -r '.read_only // false' 2>/dev/null)
ROLE_NAME=$(echo "$ROLE_DATA" | jq -r '.role // "unknown"' 2>/dev/null)
STARTED=$(echo "$ROLE_DATA" | jq -r '.started // empty' 2>/dev/null)

# Stale state detection (>30 minutes = 1800 seconds)
if [ -n "$STARTED" ]; then
  # Try GNU date first, then BSD date
  STARTED_TS=$(date -d "$STARTED" +%s 2>/dev/null || \
               date -jf '%Y-%m-%dT%H:%M:%S' "${STARTED%%Z}" +%s 2>/dev/null || \
               echo 0)
  NOW_TS=$(date +%s)
  ELAPSED=$(( NOW_TS - STARTED_TS ))
  if [ "$ELAPSED" -gt 1800 ]; then
    echo '{"decision":"allow"}'
    exit 0
  fi
fi

# Check read_only flag
if [ "$READ_ONLY" = "true" ]; then
  echo "{\"decision\":\"block\",\"reason\":\"Role '${ROLE_NAME}' is read-only — Write/Edit blocked by FORGE role enforcement\"}"
  exit 0
fi

# Default: allow
echo '{"decision":"allow"}'
