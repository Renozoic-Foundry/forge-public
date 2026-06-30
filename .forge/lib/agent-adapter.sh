#!/usr/bin/env bash
# FORGE agent-adapter.sh — Agent adapter interface
# Sourced by other FORGE scripts. Do not execute directly.
#
# Contract: each agent adapter must implement:
#   forge_agent_invoke(role, instructions_file, working_dir, spec_file)
#   forge_agent_supports_tool_scoping() → returns 0 (true) or 1 (false)
#   forge_agent_supports_system_prompt() → returns 0 (true) or 1 (false)

FORGE_AGENT_ADAPTER=""

forge_agent_load_adapter() {
  local adapter_name
  adapter_name="$(forge_config_get "agent.adapter" "generic")"
  local adapter_file="${FORGE_DIR}/adapters/agent-${adapter_name}.sh"

  if [[ ! -f "$adapter_file" ]]; then
    echo "ERROR: Agent adapter '${adapter_name}' not found at ${adapter_file}" >&2
    return 1
  fi

  source "$adapter_file"
  FORGE_AGENT_ADAPTER="$adapter_name"

  local required_fns=(forge_agent_invoke forge_agent_supports_tool_scoping forge_agent_supports_system_prompt)
  for fn in "${required_fns[@]}"; do
    if ! declare -f "$fn" > /dev/null 2>&1; then
      echo "ERROR: Agent adapter '${adapter_name}' does not implement ${fn}()" >&2
      return 1
    fi
  done

  echo "Agent adapter loaded: ${adapter_name}" >&2
}
