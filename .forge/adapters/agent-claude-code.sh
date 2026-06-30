#!/usr/bin/env bash
# FORGE agent-claude-code.sh — Claude Code agent adapter
# Optimized for Claude Code CLI with system prompt and tool scoping support.

forge_agent_invoke() {
  local role="$1"
  local instructions_file="$2"
  local working_dir="$3"
  local spec_file="${4:-}"

  if [[ ! -f "$instructions_file" ]]; then
    echo "ERROR: Role instructions not found: ${instructions_file}" >&2
    return 1
  fi

  local instructions
  instructions="$(cat "$instructions_file")"

  # Build the system prompt from role instructions
  local system_prompt="You are operating as the FORGE ${role} role within a spec-driven development pipeline."
  system_prompt+=$'\n\n'"${instructions}"

  # Build the task prompt
  local prompt=""
  if [[ -n "$spec_file" && -f "$spec_file" ]]; then
    local spec_content
    spec_content="$(cat "$spec_file")"
    prompt="Work on the following spec:\n\n${spec_content}"
  else
    prompt="Execute your role as described in the system instructions."
  fi

  echo "Invoking Claude Code: role=${role}, dir=${working_dir}" >&2

  local exit_code=0
  (
    cd "$working_dir" || exit 1
    claude --print \
      --system-prompt "$system_prompt" \
      --dangerously-skip-permissions \
      "$prompt" 2>&1
  ) || exit_code=$?

  return $exit_code
}

forge_agent_supports_tool_scoping() {
  return 0  # Claude Code supports tool scoping
}

forge_agent_supports_system_prompt() {
  return 0  # Claude Code supports system prompts
}
