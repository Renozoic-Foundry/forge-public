#!/usr/bin/env bash
# FORGE Edit-Gate — PreToolUse hook (Spec 457, fixes EA-143; schema migrated Spec 499)
# Blocks Write/Edit/NotebookEdit to the watched payload surfaces (scripts/ and — Spec 632 R4 —
# the shipped guard/hook payload: .forge/bin/, .forge/lib/, .claude-plugin/hooks/) when no
# active /implement session exists (.forge/state/implementing.json absent).
#
# Replaces the inert inline edit-gate (EA-143): the old command read a non-existent
# $CLAUDE_FILE_PATH env var (Claude Code delivers the path via stdin JSON) and blocked
# via `exit 1` (non-blocking).
#
# Schema (Spec 499): blocks via the documented PreToolUse schema
# hookSpecificOutput.permissionDecision="deny" + exit 0. The prior top-level
# {"decision":"block"} form was honored only via undocumented backward-compat (verified
# 2026-06-24), not the documented PreToolUse contract.
#
# Behavior:
#   - No payload / no file_path     -> allow
#   - jq missing                    -> allow (fail-open — same as check-commit-guard.sh)
#   - Path not under a watched dir  -> allow
#   - implementing.json exists      -> allow (active /implement)
#   - Watched path, no marker       -> block (specless edit attempt)
#
# Spec 632 R4: extending the watch set to .forge/bin/**, .forge/lib/**, .claude-plugin/hooks/**
# closes the post-Spec-558 gap where the shipped payload (including the guard scripts and hooks
# themselves) was uncovered — the original scripts/ target predates the payload move. No
# bootstrap self-edit deadlock results: .forge/state/implementing.json is itself OUTSIDE the
# watched set, so any active /implement session satisfies the gate for edits to the payload
# (DA finding — structurally identical to the pre-632 scripts/ coverage). The authority guard
# (.forge/bin/check-authority-guard.sh deny set) is the stronger, separate control on the guard
# scripts; this watch-set extension covers the rest of the payload.
#
# When blocked, deny is a HARD BLOCK — it raises no in-session permission dialog. To
# make a legitimate non-spec edit, run it yourself in the terminal, or start
# /implement <spec-number> first.

# Read tool input from stdin (Claude Code passes JSON with tool_input.file_path).
INPUT=$(cat)

# Fast path: if jq is not available, fail-open (matches check-commit-guard.sh).
if ! command -v jq >/dev/null 2>&1; then
  exit 0
fi

# Extract the edited file path from stdin JSON.
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.path // empty' 2>/dev/null)
if [ -z "$FILE" ]; then
  exit 0
fi

# Normalize: backslashes -> slashes (Windows paths), strip leading ./, strip an absolute
# repo-root prefix so an absolute path compares the same as a repo-relative one.
REL=$(printf '%s' "$FILE" | tr '\\' '/')
REL="${REL#./}"
ROOT=$(git rev-parse --show-toplevel 2>/dev/null || true)
if [ -n "$ROOT" ]; then
  ROOT=$(printf '%s' "$ROOT" | tr '\\' '/')
  case "$REL" in
    "$ROOT"/*) REL="${REL#"$ROOT"/}" ;;
  esac
fi

# Only gate the watched paths (Spec 632 R4 adds the shipped payload surfaces).
case "$REL" in
  scripts/*|.forge/bin/*|.forge/lib/*|.claude-plugin/hooks/*)
    if [ ! -f ".forge/state/implementing.json" ]; then
      REASON="EDIT-GATE (Spec 457): No active /implement session. Run /implement <spec-number> before editing ${REL}. "
      REASON+="This is a hard block — if it is a legitimate non-spec edit, run it yourself in the terminal."
      jq -nc --arg r "$REASON" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
      exit 0
    fi
    ;;
esac
exit 0
