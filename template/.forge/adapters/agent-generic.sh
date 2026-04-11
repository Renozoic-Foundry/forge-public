#!/usr/bin/env bash
# FORGE agent-generic.sh — Generic agent adapter
# Works with any CLI-invokable AI coding agent by injecting role instructions
# into AGENTS.md in the working directory.

forge_agent_invoke() {
  local role="$1"
  local instructions_file="$2"
  local working_dir="$3"
  local spec_file="${4:-}"

  local agent_command
  agent_command="$(forge_config_get "agent.command" "claude")"

  # Read role instructions
  if [[ ! -f "$instructions_file" ]]; then
    echo "ERROR: Role instructions not found: ${instructions_file}" >&2
    return 1
  fi

  local instructions
  instructions="$(cat "$instructions_file")"

  # Inject role instructions into the working directory's AGENTS.md
  local agents_md="${working_dir}/AGENTS.md"
  if [[ -f "$agents_md" ]]; then
    # Backup original
    cp "$agents_md" "${agents_md}.forge-backup"
  fi

  # Append role-specific section to AGENTS.md
  {
    echo ""
    echo "## Active FORGE Role"
    echo ""
    echo "$instructions"
    echo ""
    if [[ -n "$spec_file" && -f "$spec_file" ]]; then
      echo "## Active Spec"
      echo ""
      cat "$spec_file"
    fi
  } >> "$agents_md"

  echo "Invoking agent: ${agent_command} (role: ${role})" >&2

  # Build the prompt for the agent
  local prompt="You are operating as the FORGE ${role} role. Follow the instructions in the 'Active FORGE Role' section of AGENTS.md. "
  if [[ -n "$spec_file" ]]; then
    prompt+="The spec to work on is included in the 'Active Spec' section of AGENTS.md."
  fi

  # Invoke the agent CLI
  local exit_code=0
  (
    cd "$working_dir" || exit 1
    "$agent_command" --print "$prompt" 2>&1
  ) || exit_code=$?

  # Restore original AGENTS.md
  if [[ -f "${agents_md}.forge-backup" ]]; then
    mv "${agents_md}.forge-backup" "$agents_md"
  fi

  return $exit_code
}

forge_agent_supports_tool_scoping() {
  return 1  # Generic adapter does not support tool scoping
}

forge_agent_supports_system_prompt() {
  return 1  # Generic adapter uses AGENTS.md injection instead
}
